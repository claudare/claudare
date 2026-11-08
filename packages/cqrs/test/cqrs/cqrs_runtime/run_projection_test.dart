import 'dart:async';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import 'projection_test_support.dart';

void main() {
  late ControlledMemoryEventStore store;
  late CqrsTestRuntime runtime;

  setUp(() {
    store = ControlledMemoryEventStore();
    runtime = CqrsTestRuntime(eventStore: store);
    runtime.eventRegistry.add(const ProjectionEventCodec());
    addTearDown(store.closeChanges);
  });

  ProjectionRun start<T extends Object>(
    RecordingProjection<T> projection, {
    int logPosition = -1,
    List<AsyncGate> gates = const [],
    Matcher? failure,
  }) {
    final run = runtime.runProjection(projection, logPosition: logPosition);
    addTearDown(() async {
      for (final gate in gates) {
        gate.release();
      }
      if (failure == null) {
        await run.cancel();
      } else {
        await expectLater(run.cancel(), throwsA(failure));
      }
    });
    return run;
  }

  test('returns a handle and loads once before delivering events', () async {
    await appendProjectionEvent(store, 'existing');
    final gate = AsyncGate();
    final projection = RecordingProjection<ProjectionEvent>(
      beforeLoad: gate.wait,
    );

    final run = start(projection, gates: [gate]);
    expect(run, isA<ProjectionRun>());
    await gate.entered.future;
    expect(projection.loadedPositions, [-1]);
    expect(projection.events, isEmpty);
    expect(store.subscriptions.count, 0);

    gate.release();
    await projection.applications.waitFor(1);
    await run.cancel();
    expect(projection.loads.count, 1);
    expect(projection.events.single.event.value, 'existing');
  });

  test('replays the existing log from the beginning by default', () async {
    await appendProjectionEvent(store, 'first');
    await appendProjectionEvent(store, 'second');
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await projection.applications.waitFor(2);
    await run.cancel();

    expect(projection.events.map((event) => event.event.value), [
      'first',
      'second',
    ]);
    expect(projection.events.map((event) => event.logPosition), [0, 1]);
  });

  test('loads the checkpoint and replays strictly after it', () async {
    for (var index = 0; index < 4; index++) {
      await appendProjectionEvent(store, '$index');
    }
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection, logPosition: 1);

    await projection.applications.waitFor(2);
    await run.cancel();

    expect(projection.loadedPositions, [1]);
    expect(store.positions.first, 2);
    expect(projection.events.map((event) => event.event.value), ['2', '3']);
    expect(projection.events.map((event) => event.logPosition), [2, 3]);
  });

  test('preserves event actors, paths, and timestamps', () async {
    final time = projectionTime.add(const Duration(days: 2));
    await appendProjectionEvent(
      store,
      'payload',
      actor: 'remote-actor',
      path: 'notes/two',
      occuredAt: time,
    );
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await projection.applications.waitFor(1);
    await run.cancel();

    final envelope = projection.events.single;
    expect(envelope.event.value, 'payload');
    expect(envelope.actor, 'remote-actor');
    expect(envelope.streamPath, 'notes/two');
    expect(envelope.occuredAt, time);
    expect(envelope.logPosition, 0);
  });

  for (final (name, filter, values) in [
    ('exact', const LogFilter.exact('notes/one'), ['0', '3']),
    ('prefix', const LogFilter.startsWith('notes/'), ['0', '2', '3']),
    ('all', const LogFilter.all(), ['0', '1', '2', '3']),
  ]) {
    test('applies $name filter matches across pages', () async {
      for (final (index, path) in [
        'notes/one',
        'other',
        'notes/two',
        'notes/one',
      ].indexed) {
        await appendProjectionEvent(store, '$index', path: path);
      }
      final projection = RecordingProjection<ProjectionEvent>(filter: filter);
      final run = start(projection);

      await projection.applications.waitFor(values.length);
      await run.cancel();

      expect(projection.events.map((event) => event.event.value), values);
      expect(
        projection.events.map((event) => event.logPosition),
        values.map(int.parse),
      );
    });
  }

  test(
    'continues delivering events after catching up with an empty log',
    () async {
      final projection = RecordingProjection<ProjectionEvent>();
      final run = start(projection);
      await store.emptyReads.waitFor(1);

      await appendProjectionEvent(store, 'first');
      await projection.applications.waitFor(1);
      await appendProjectionEvent(store, 'second');
      await projection.applications.waitFor(2);
      await run.cancel();

      expect(projection.events.map((event) => event.event.value), [
        'first',
        'second',
      ]);
      expect(projection.events.map((event) => event.logPosition), [0, 1]);
    },
  );

  test('includes events committed while loading', () async {
    final gate = AsyncGate();
    final projection = RecordingProjection<ProjectionEvent>(
      beforeLoad: gate.wait,
    );
    final run = start(projection, gates: [gate]);
    await gate.entered.future;

    await appendProjectionEvent(store, 'during load');
    gate.release();
    await projection.applications.waitFor(1);
    await run.cancel();

    expect(projection.events.single.event.value, 'during load');
  });

  test('skips erased records without decoding or applying them', () async {
    await appendProjectionEvent(store, 'erased', path: 'notes/deleted');
    await appendProjectionEvent(
      store,
      '',
      path: 'notes/deleted',
      encodedEvent: EncodedEvent.streamDeleted(),
    );
    await appendProjectionEvent(store, 'retained');
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await projection.applications.waitFor(1);
    await run.cancel();

    expect(projection.events.single.event.value, 'retained');
    expect(projection.events.single.logPosition, 2);
    expect(projection.deletions.single.logPosition, 1);
  });

  test('forwards deletion metadata without decoding it as an event', () async {
    final time = projectionTime.add(const Duration(days: 1));
    await appendProjectionEvent(
      store,
      '',
      path: 'notes/deleted',
      actor: 'deleting-actor',
      occuredAt: time,
      encodedEvent: EncodedEvent.streamDeleted(),
    );
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await projection.deletionCalls.waitFor(1);
    await run.cancel();

    final deletion = projection.deletions.single;
    expect(deletion.actor, 'deleting-actor');
    expect(deletion.streamPath, 'notes/deleted');
    expect(deletion.occuredAt, time);
    expect(deletion.logPosition, 0);
    expect(projection.events, isEmpty);
  });

  for (final deletion in [false, true]) {
    final callback = deletion ? 'deletion' : 'application';

    Future<void> seedCallbacks() async {
      await appendProjectionEvent(
        store,
        'first',
        path: 'notes/first',
        encodedEvent: deletion ? EncodedEvent.streamDeleted() : null,
      );
      await appendProjectionEvent(store, 'second');
    }

    RecordingProjection<ProjectionEvent> gatedProjection(AsyncGate gate) =>
        RecordingProjection<ProjectionEvent>(
          beforeApply: deletion ? null : gate.wait,
          beforeDeletion: deletion ? gate.wait : null,
        );

    test(
      'awaits an active $callback before delivering the next event',
      () async {
        await seedCallbacks();
        final gate = AsyncGate();
        final projection = gatedProjection(gate);
        final run = start(projection, gates: [gate]);
        await gate.entered.future;

        // Drain queued work while the first callback remains blocked.
        await Future<void>(() {});
        expect(projection.events.length, deletion ? 0 : 1);

        gate.release();
        await projection.applications.waitFor(deletion ? 1 : 2);
        await run.cancel();
        expect(projection.events.last.event.value, 'second');
      },
    );

    test(
      'cancellation waits for an active $callback and skips later events',
      () async {
        await seedCallbacks();
        final gate = AsyncGate();
        final projection = gatedProjection(gate);
        final run = start(projection, gates: [gate]);
        await gate.entered.future;
        var done = false;
        final completion = run.done.then((_) => done = true);
        var cancelled = false;
        final cancellation = run.cancel().then((_) => cancelled = true);

        await store.cancellations.waitFor(1);
        expect(done, isFalse);
        expect(cancelled, isFalse);

        gate.release();
        await cancellation;
        await completion;
        expect(projection.events.length, deletion ? 0 : 1);
        expect(store.hasChangeListener, isFalse);
      },
    );
  }

  test('can cancel before scheduled loading starts', () async {
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await run.cancel();
    await run.done;

    expect(projection.loadedPositions, isEmpty);
    expect(store.subscriptions.count, 0);
  });

  test(
    'cancellation during loading waits for load and prevents replay',
    () async {
      await appendProjectionEvent(store, 'existing');
      final gate = AsyncGate();
      final projection = RecordingProjection<ProjectionEvent>(
        beforeLoad: gate.wait,
      );
      final run = start(projection, gates: [gate]);
      await gate.entered.future;
      var cancelled = false;
      final cancellation = run.cancel().then((_) => cancelled = true);

      await Future<void>(() {});
      expect(cancelled, isFalse);
      gate.release();
      await cancellation;
      await run.done;

      expect(projection.events, isEmpty);
      expect(store.subscriptions.count, 0);
      expect(store.positions, isEmpty);
    },
  );

  test('cancels an idle projection without another notification', () async {
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);
    await store.emptyReads.waitFor(1);

    await run.cancel();
    await run.done;

    expect(store.hasChangeListener, isFalse);
    expect(store.cancellations.count, 1);
  });

  test('can cancel during an active storage read', () async {
    await appendProjectionEvent(store, 'existing');
    final gate = AsyncGate();
    store.afterRead = (_) => gate.wait();
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection, gates: [gate]);
    await gate.entered.future;

    final cancellation = run.cancel();
    gate.release();
    await cancellation;
    await run.done;

    expect(projection.events, isEmpty);
    expect(store.hasChangeListener, isFalse);
  });

  test(
    'repeated cancellation shares cleanup and completes successfully',
    () async {
      final projection = RecordingProjection<ProjectionEvent>();
      final run = start(projection);
      await store.emptyReads.waitFor(1);

      await Future.wait([run.cancel(), run.cancel()]);
      await run.cancel();
      await run.done;

      expect(store.cancellations.count, 1);
    },
  );

  test('completes done when the change stream closes', () async {
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);
    await store.emptyReads.waitFor(1);

    await store.closeChanges();
    await run.done;

    expect(store.hasChangeListener, isFalse);
  });

  for (final source in [
    'load',
    'application',
    'deletion',
    'read',
    'notification',
  ]) {
    test(
      '$source failures reach done and cancellation after cleanup',
      () async {
        final error = StateError('$source failed');
        final trace = StackTrace.fromString('$source failure trace');
        Future<void> failOperation() => Future<void>.error(error, trace);
        if (source == 'application') {
          await appendProjectionEvent(store, 'failing');
        } else if (source == 'deletion') {
          await appendProjectionEvent(
            store,
            '',
            encodedEvent: EncodedEvent.streamDeleted(),
          );
        } else if (source == 'read') {
          store.afterRead = (_) => failOperation();
        }
        final projection = RecordingProjection<ProjectionEvent>(
          beforeLoad: source == 'load' ? failOperation : null,
          beforeApply: source == 'application' ? failOperation : null,
          beforeDeletion: source == 'deletion' ? failOperation : null,
        );
        final run = start(projection, failure: same(error));
        final expectation = run.done.then<void>(
          (_) => fail('Expected the projection to fail'),
          onError: (Object actual, StackTrace stackTrace) {
            expect(actual, same(error));
            expect(stackTrace.toString(), trace.toString());
          },
        );
        if (source == 'notification') {
          await store.emptyReads.waitFor(1);
          store.failNotifications(error, trace);
        }

        await expectation;
        expect(store.hasChangeListener, isFalse);
        expect(store.cancellations.count, source == 'load' ? 0 : 1);
        await expectLater(run.cancel(), throwsA(same(error)));

        final applied = projection.events.length;
        final notificationCount = store.notifications.count;
        await appendProjectionEvent(store, 'later', path: 'notes/later');
        await store.notifications.waitFor(notificationCount + 1);
        expect(projection.events, hasLength(applied));
      },
    );
  }

  for (final (name, event) in [
    ('unregistered', EncodedEvent(kind: 'unknown', bytes: Uint8List(0))),
    (
      'malformed',
      EncodedEvent(kind: 'projection-event', bytes: Uint8List.fromList([255])),
    ),
  ]) {
    test(
      '$name event decoding failures reach done and release resources',
      () async {
        await appendProjectionEvent(store, '', encodedEvent: event);
        final projection = RecordingProjection<ProjectionEvent>();
        final run = start(projection, failure: isA<EventCodecException>());

        await expectLater(run.done, throwsA(isA<EventCodecException>()));

        expect(projection.events, isEmpty);
        expect(store.hasChangeListener, isFalse);
        expect(store.cancellations.count, 1);
      },
    );
  }

  test('a decoded event of the wrong projection type fails done', () async {
    await appendProjectionEvent(store, 'wrong type');
    final projection = RecordingProjection<int>();
    final run = start(projection, failure: isA<StateError>());

    await expectLater(run.done, throwsStateError);

    expect(projection.events, isEmpty);
    expect(store.hasChangeListener, isFalse);
    expect(store.cancellations.count, 1);
  });
}
