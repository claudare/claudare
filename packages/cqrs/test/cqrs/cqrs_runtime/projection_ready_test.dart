import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import 'projection_test_support.dart';

void main() {
  late _ReadyStore store;
  late CqrsTestRuntime runtime;

  setUp(() {
    store = _ReadyStore();
    runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const ProjectionEventCodec());
    addTearDown(store.closeChanges);
  });

  ProjectionRun start(
    RecordingProjection<ProjectionEvent> projection, {
    List<AsyncGate> gates = const [],
    Object? failure,
  }) {
    final run = runtime.runProjection(projection);
    addTearDown(() async {
      for (final gate in gates) {
        gate.release();
      }
      if (failure == null) {
        await run.cancel();
      } else {
        await expectLater(run.cancel(), throwsA(same(failure)));
      }
    });
    return run;
  }

  test('ready starts pending and waits for loading', () async {
    final gate = AsyncGate();
    final run = start(
      RecordingProjection(beforeLoad: gate.wait),
      gates: [gate],
    );
    var ready = false;
    final completion = run.ready.then((_) => ready = true);

    await gate.entered.future;
    expect(ready, isFalse);

    gate.release();
    await completion;
  });

  test('ready completes for an empty log', () async {
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await run.ready;

    expect(projection.loads.count, 1);
    expect(projection.events, isEmpty);
  });

  test('ready waits for the target position lookup', () async {
    final gate = AsyncGate();
    store.readPosition = (_) async {
      await gate.wait();
      return -1;
    };
    final run = start(RecordingProjection(), gates: [gate]);
    var ready = false;
    final completion = run.ready.then((_) => ready = true);

    await gate.entered.future;
    await Future<void>(() {});
    expect(ready, isFalse);

    gate.release();
    await completion;
  });

  for (final checkpoint in [0, 1]) {
    test(
      'ready completes when checkpoint $checkpoint covers the target',
      () async {
        await appendProjectionEvent(store, 'existing');
        final projection = RecordingProjection<ProjectionEvent>(
          loadedLogPosition: checkpoint,
        );
        final run = start(projection);

        await run.ready;

        expect(projection.events, isEmpty);
      },
    );
  }

  for (final deletion in [false, true]) {
    test(
      'ready waits for the final ${deletion ? 'deletion' : 'event'} handler',
      () async {
        await appendProjectionEvent(store, 'first');
        await appendProjectionEvent(
          store,
          'last',
          path: 'notes/last',
          encodedEvent: deletion ? EncodedEvent.streamDeleted() : null,
        );
        final gate = AsyncGate();
        var applications = 0;
        final projection = RecordingProjection<ProjectionEvent>(
          beforeApply: () async {
            if (++applications == 2) await gate.wait();
          },
          beforeDeletion: deletion ? gate.wait : null,
        );
        final run = start(projection, gates: [gate]);
        var ready = false;
        final completion = run.ready.then((_) => ready = true);

        await gate.entered.future;
        await Future<void>(() {});
        expect(ready, isFalse);

        gate.release();
        await completion;
        expect(projection.events.length, deletion ? 1 : 2);
        expect(projection.deletions.length, deletion ? 1 : 0);
      },
    );
  }

  for (final filter in [
    const LogFilter.exact('notes/one'),
    const LogFilter.startsWith('notes/'),
  ]) {
    test(
      'ready follows global positions across filtered pages for $filter',
      () async {
        for (final path in [
          'notes/one',
          'other',
          'other',
          'notes/one',
          'other',
        ]) {
          await appendProjectionEvent(store, path, path: path);
        }
        final projection = RecordingProjection<ProjectionEvent>(
          filter: filter,
          loadedLogPosition: 0,
        );
        final run = start(projection);

        await run.ready;

        expect(projection.events.map((event) => event.logPosition), [3]);
      },
    );
  }

  test('ready counts an erased record at the replay target', () async {
    await appendProjectionEvent(
      store,
      'erased',
      encodedEvent: EncodedEvent.eventErased(),
    );
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await run.ready;

    expect(projection.events, isEmpty);
    expect(store.reads.count, greaterThan(0));
  });

  test(
    'ready keeps its initial target when new events arrive during replay',
    () async {
      await appendProjectionEvent(store, 'initial');
      final gate = AsyncGate();
      var applications = 0;
      final projection = RecordingProjection<ProjectionEvent>(
        beforeApply: () async {
          if (++applications == 1) {
            await appendProjectionEvent(store, 'later');
          } else {
            await gate.wait();
          }
        },
      );
      final run = start(projection, gates: [gate]);

      await gate.entered.future;
      await run.ready;
      expect(projection.events.map((event) => event.event.value), [
        'initial',
        'later',
      ]);
      gate.release();
    },
  );

  for (final source in ['load', 'target', 'read', 'application', 'deletion']) {
    test(
      '$source failure reaches ready and done with its original trace',
      () async {
        final error = StateError('$source failed');
        final trace = StackTrace.fromString('$source original trace');
        Future<void> failOperation() => Future<void>.error(error, trace);
        if (source == 'application' ||
            source == 'read' ||
            source == 'deletion') {
          await appendProjectionEvent(
            store,
            'event',
            encodedEvent: source == 'deletion'
                ? EncodedEvent.streamDeleted()
                : null,
          );
        }
        if (source == 'target') {
          store.readPosition = (_) => Future<int>.error(error, trace);
        }
        if (source == 'read') store.afterRead = (_) => failOperation();
        final run = start(
          RecordingProjection(
            beforeLoad: source == 'load' ? failOperation : null,
            beforeApply: source == 'application' ? failOperation : null,
            beforeDeletion: source == 'deletion' ? failOperation : null,
          ),
          failure: error,
        );
        Future<void> expectFailure(Future<void> future) => future.then<void>(
          (_) => fail('Expected $source failure'),
          onError: (Object actual, StackTrace actualTrace) {
            expect(actual, same(error));
            expect(actualTrace.toString(), trace.toString());
          },
        );

        await Future.wait([expectFailure(run.ready), expectFailure(run.done)]);
      },
    );
  }

  test('cancellation before startup settles ready', () async {
    final run = start(RecordingProjection());
    final expectation = expectLater(
      run.ready,
      throwsA(isA<ProjectionStoppedException>()),
    );

    await run.cancel();
    await expectation;
  });

  test(
    'cancellation during replay does not report successful readiness',
    () async {
      await appendProjectionEvent(store, 'event');
      final gate = AsyncGate();
      final run = start(
        RecordingProjection(beforeApply: gate.wait),
        gates: [gate],
      );
      final expectation = expectLater(
        run.ready,
        throwsA(isA<ProjectionStoppedException>()),
      );
      await gate.entered.future;

      final cancellation = run.cancel();
      gate.release();
      await cancellation;
      await expectation;
    },
  );
}

class _ReadyStore extends ControlledMemoryEventStore {
  Future<int> Function(LogFilter)? readPosition;

  @override
  Future<int> getLogPosition(LogFilter filter) =>
      readPosition?.call(filter) ?? super.getLogPosition(filter);
}
