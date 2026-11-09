import 'dart:async';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/projection_runner.dart';
import 'package:test/test.dart';

import 'projection_test_support.dart';

void main() {
  late ControlledMemoryEventStore store;
  late EventRegistry registry;

  setUp(() {
    store = ControlledMemoryEventStore();
    registry = EventRegistry()..add(const ProjectionEventCodec());
    addTearDown(store.closeChanges);
  });

  ProjectionRunner<T> start<T extends Object>(
    RecordingProjection<T> projection, {
    List<AsyncGate> gates = const [],
    Matcher? failure,
  }) {
    final run = ProjectionRunner(
      projection,
      logPlayer: LogPlayer(store),
      eventRegistry: registry,
    );
    run.start().ignore();
    addTearDown(() async {
      for (final gate in gates) {
        gate.release();
      }
      if (failure == null) {
        await run.stop();
      } else {
        await expectLater(run.stop(), throwsA(failure));
      }
    });
    return run;
  }

  Future<void> expectFailure(
    Future<void> future,
    Object error,
    StackTrace trace,
  ) => future.then<void>(
    (_) => fail('Expected the projection to fail'),
    onError: (Object actual, StackTrace actualTrace) {
      expect(actual, same(error));
      expect(actualTrace.toString(), trace.toString());
    },
  );

  test('starts only when explicitly requested and returns done', () async {
    final projection = RecordingProjection<ProjectionEvent>();
    final runner = ProjectionRunner(
      projection,
      logPlayer: LogPlayer(store),
      eventRegistry: registry,
    );
    await Future<void>(() {});
    expect(projection.loads.count, 0);

    expect(runner.start(), same(runner.done));
    await runner.ready;
    await runner.stop();
    expect(projection.loads.count, 1);
  });

  test('rejects a second start', () async {
    final runner = start(RecordingProjection<ProjectionEvent>());

    expect(runner.start, throwsStateError);
    await runner.stop();
  });

  test(
    'stopping before start settles readiness and prevents starting',
    () async {
      final projection = RecordingProjection<ProjectionEvent>();
      final runner = ProjectionRunner(
        projection,
        logPlayer: LogPlayer(store),
        eventRegistry: registry,
      );
      final readiness = expectLater(
        runner.ready,
        throwsA(isA<ProjectionStoppedException>()),
      );

      await runner.stop();
      await runner.stop();
      await runner.done;
      await readiness;

      expect(runner.start, throwsStateError);
      expect(projection.loads.count, 0);
    },
  );

  test('waits for loading before replaying available events', () async {
    await appendProjectionEvent(store, 'existing');
    final gate = AsyncGate();
    final projection = RecordingProjection<ProjectionEvent>(
      beforeLoad: gate.wait,
    );

    final run = start(projection, gates: [gate]);
    var ready = false;
    final completion = run.ready.then((_) => ready = true);
    await gate.entered.future;
    expect(ready, isFalse);
    expect(projection.loads.count, 1);
    expect(projection.events, isEmpty);

    await appendProjectionEvent(store, 'during load');
    gate.release();
    await completion;
    expect(projection.loads.count, 1);
    expect(projection.events.map((event) => event.event.value), [
      'existing',
      'during load',
    ]);
  });

  test('replays the existing log from the beginning by default', () async {
    await appendProjectionEvent(store, 'first');
    await appendProjectionEvent(store, 'second');
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await run.ready;

    expect(projection.events.map((event) => event.event.value), [
      'first',
      'second',
    ]);
    expect(projection.events.map((event) => event.logPosition), [0, 1]);
  });

  test(
    'replays matching events strictly after the loaded checkpoint',
    () async {
      await appendProjectionEvent(store, 'already applied');
      await appendProjectionEvent(store, 'unrelated', path: 'other');
      await appendProjectionEvent(store, 'remaining');
      final projection = RecordingProjection<ProjectionEvent>(
        filter: const LogFilter.exact('notes/one'),
        loadedLogPosition: 0,
      );
      final run = start(projection);

      await run.ready;

      expect(projection.events.single.event.value, 'remaining');
      expect(projection.events.single.logPosition, 2);
    },
  );

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

    await run.ready;

    final envelope = projection.events.single;
    expect(envelope.event.value, 'payload');
    expect(envelope.actor, 'remote-actor');
    expect(envelope.streamPath, 'notes/two');
    expect(envelope.occuredAt, time);
    expect(envelope.logPosition, 0);
  });

  test(
    'continues delivering events after catching up with an empty log',
    () async {
      final projection = RecordingProjection<ProjectionEvent>();
      final run = start(projection);
      await run.ready;
      expect(projection.events, isEmpty);

      await appendProjectionEvent(store, 'first');
      await projection.applications.waitFor(1);
      await appendProjectionEvent(store, 'second');
      await projection.applications.waitFor(2);
      await run.stop();

      expect(projection.events.map((event) => event.event.value), [
        'first',
        'second',
      ]);
      expect(projection.events.map((event) => event.logPosition), [0, 1]);
    },
  );

  test('skips erased records without decoding or applying them', () async {
    await appendProjectionEvent(store, 'retained');
    await appendProjectionEvent(
      store,
      '',
      encodedEvent: EncodedEvent.eventErased(),
    );
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);

    await run.ready;

    expect(projection.events.single.event.value, 'retained');
    expect(projection.events.single.logPosition, 0);
    expect(projection.deletions, isEmpty);
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

    await run.ready;

    final deletion = projection.deletions.single;
    expect(deletion.actor, 'deleting-actor');
    expect(deletion.streamPath, 'notes/deleted');
    expect(deletion.occuredAt, time);
    expect(deletion.logPosition, 0);
    expect(projection.events, isEmpty);
  });

  test(
    'awaits an active application before delivering the next event',
    () async {
      await appendProjectionEvent(store, 'first', path: 'notes/first');
      await appendProjectionEvent(store, 'second');
      final gate = AsyncGate();
      final projection = RecordingProjection<ProjectionEvent>(
        beforeApply: gate.wait,
      );
      final run = start(projection, gates: [gate]);
      await gate.entered.future;

      // Drain queued work while the first application remains blocked.
      await Future<void>(() {});
      expect(projection.events.length, 1);

      gate.release();
      await projection.applications.waitFor(2);
      await run.stop();
      expect(projection.events.last.event.value, 'second');
    },
  );

  test(
    'cancellation waits for an active application and skips later events',
    () async {
      await appendProjectionEvent(store, 'first', path: 'notes/first');
      await appendProjectionEvent(store, 'second');
      final gate = AsyncGate();
      final projection = RecordingProjection<ProjectionEvent>(
        beforeApply: gate.wait,
      );
      final run = start(projection, gates: [gate]);
      await gate.entered.future;
      final readiness = expectLater(
        run.ready,
        throwsA(isA<ProjectionStoppedException>()),
      );
      var done = false;
      final completion = run.done.then((_) => done = true);
      var cancelled = false;
      final cancellation = run.stop().then((_) => cancelled = true);

      await Future<void>(() {});
      expect(done, isFalse);
      expect(cancelled, isFalse);

      gate.release();
      await cancellation;
      await completion;
      await readiness;
      expect(projection.events.map((event) => event.event.value), ['first']);
    },
  );

  test('can stop immediately after starting', () async {
    await appendProjectionEvent(store, 'existing');
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);
    final readiness = expectLater(
      run.ready,
      throwsA(isA<ProjectionStoppedException>()),
    );

    await run.stop();
    await readiness;

    expect(projection.events, isEmpty);
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
      final cancellation = run.stop().then((_) => cancelled = true);

      await Future<void>(() {});
      expect(cancelled, isFalse);
      gate.release();
      await cancellation;
      await run.done;

      expect(projection.events, isEmpty);
    },
  );

  test(
    'stopping an idle runner is repeatable and releases its subscription',
    () async {
      final projection = RecordingProjection<ProjectionEvent>();
      final run = start(projection);
      await run.ready;

      await Future.wait([run.stop(), run.stop()]);
      await run.stop();
      await run.done;

      expect(store.hasChangeListener, isFalse);
      await appendProjectionEvent(store, 'after stop');
      await Future<void>(() {});
      expect(projection.events, isEmpty);
    },
  );

  test('completes done when the change stream closes', () async {
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection);
    await run.ready;

    await store.closeChanges();
    await run.done;
  });

  test('load failure reaches ready, done, and stop', () async {
    await appendProjectionEvent(store, 'existing');
    final error = StateError('load failed');
    final trace = StackTrace.fromString('load failure trace');
    final projection = RecordingProjection<ProjectionEvent>(
      beforeLoad: () => Future<void>.error(error, trace),
    );
    final run = start(projection, failure: same(error));

    await Future.wait([
      expectFailure(run.ready, error, trace),
      expectFailure(run.done, error, trace),
    ]);

    await expectLater(run.stop(), throwsA(same(error)));
    expect(projection.events, isEmpty);
  });

  test('application failure reaches ready and done after cleanup', () async {
    await appendProjectionEvent(store, 'failing');
    await appendProjectionEvent(store, 'later');
    final error = StateError('application failed');
    final trace = StackTrace.fromString('application failure trace');
    final projection = RecordingProjection<ProjectionEvent>(
      beforeApply: () => Future<void>.error(error, trace),
    );
    final run = start(projection, failure: same(error));

    await Future.wait([
      expectFailure(run.ready, error, trace),
      expectFailure(run.done, error, trace),
    ]);

    expect(store.hasChangeListener, isFalse);
    await expectLater(run.stop(), throwsA(same(error)));
    expect(projection.events.map((event) => event.event.value), ['failing']);
  });

  test('deletion failure reaches ready, done, and stop', () async {
    await appendProjectionEvent(
      store,
      '',
      encodedEvent: EncodedEvent.streamDeleted(),
    );
    final error = StateError('deletion failed');
    final trace = StackTrace.fromString('deletion failure trace');
    final projection = RecordingProjection<ProjectionEvent>(
      beforeDeletion: () => Future<void>.error(error, trace),
    );
    final run = start(projection, failure: same(error));

    await Future.wait([
      expectFailure(run.ready, error, trace),
      expectFailure(run.done, error, trace),
    ]);

    await expectLater(run.stop(), throwsA(same(error)));
  });

  test('source failure during replay reaches ready, done, and stop', () async {
    final error = StateError('read failed');
    final trace = StackTrace.fromString('read failure trace');
    store.afterRead = (_) => Future<void>.error(error, trace);
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection, failure: same(error));

    await Future.wait([
      expectFailure(run.ready, error, trace),
      expectFailure(run.done, error, trace),
    ]);

    await expectLater(run.stop(), throwsA(same(error)));
  });

  test('source failure after readiness reaches done and stop', () async {
    final error = StateError('notification failed');
    final trace = StackTrace.fromString('notification failure trace');
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection, failure: same(error));
    await run.ready;
    final completion = expectFailure(run.done, error, trace);

    store.failNotifications(error, trace);
    await completion;

    await run.ready;
    await expectLater(run.stop(), throwsA(same(error)));
  });

  test('decoding failure reaches done without applying the event', () async {
    await appendProjectionEvent(
      store,
      '',
      encodedEvent: EncodedEvent(kind: 'unknown', bytes: Uint8List(0)),
    );
    final projection = RecordingProjection<ProjectionEvent>();
    final run = start(projection, failure: isA<EventCodecException>());

    await expectLater(run.done, throwsA(isA<EventCodecException>()));

    expect(projection.events, isEmpty);
  });

  test('a decoded event of the wrong projection type fails done', () async {
    await appendProjectionEvent(store, 'wrong type');
    final projection = RecordingProjection<int>();
    final run = start(projection, failure: isA<StateError>());

    await expectLater(run.done, throwsStateError);

    expect(projection.events, isEmpty);
  });

  for (final checkpoint in [0, 1]) {
    test(
      'ready completes when no events follow checkpoint $checkpoint',
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

  test('ready waits for the final event handler', () async {
    await appendProjectionEvent(store, 'first');
    await appendProjectionEvent(store, 'last', path: 'notes/last');
    final gate = AsyncGate();
    var applications = 0;
    final projection = RecordingProjection<ProjectionEvent>(
      beforeApply: () async {
        if (++applications == 2) await gate.wait();
      },
    );
    final run = start(projection, gates: [gate]);
    var ready = false;
    final completion = run.ready.then((_) => ready = true);

    await gate.entered.future;
    await Future<void>(() {});
    expect(ready, isFalse);

    gate.release();
    await completion;
    expect(projection.events.length, 2);
  });

  test(
    'ready waits for events notified during replay to finish applying',
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
      var ready = false;
      final completion = run.ready.then((_) => ready = true);

      await gate.entered.future;
      await Future<void>(() {});
      expect(ready, isFalse);
      expect(projection.events.map((event) => event.event.value), [
        'initial',
        'later',
      ]);
      gate.release();
      await completion;
    },
  );
}
