import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import 'projection_test_support.dart'
    show
        AsyncGate,
        ControlledMemoryEventStore,
        ProjectionEvent,
        ProjectionEventCodec,
        appendProjectionEvent,
        projectionTime;

void main() {
  late ControlledMemoryEventStore store;
  late EventRegistry registry;
  late ProjectionResolver resolver;

  setUp(() {
    store = ControlledMemoryEventStore();
    registry = EventRegistry()..add(const ProjectionEventCodec());
    resolver = ProjectionResolver(
      logPlayer: LogPlayer(store),
      eventRegistry: registry,
    );
    addTearDown(store.closeChanges);
  });

  LiveProjection<_Model<T>, T> create<T extends Object>(
    _Projection<T> projection, {
    Matcher? failure,
    LogPlayer? logPlayer,
  }) {
    final live = LiveProjection(
      projection,
      logPlayer: logPlayer ?? LogPlayer(store),
      eventRegistry: registry,
    );
    addTearDown(() async {
      if (failure == null) {
        await live.stop();
      } else {
        await expectLater(live.stop(), throwsA(failure));
      }
    });
    return live;
  }

  AsyncGate gate() {
    final gate = AsyncGate();
    addTearDown(gate.release);
    return gate;
  }

  test(
    'runtime projections replay and follow events using its registry',
    () async {
      final runtime = CqrsTestRuntime(eventStore: store);
      runtime.eventRegistry.add(const ProjectionEventCodec());
      await appendProjectionEvent(store, 'existing');
      final live = runtime.liveProjection(_Projection<ProjectionEvent>());
      addTearDown(live.stop);

      expect(_values(await live.start()), ['existing']);
      final updated = live.updates.firstWhere(
        (model) => model.events.length == 2,
      );
      await appendProjectionEvent(store, 'new');

      expect(_values(await updated), ['existing', 'new']);
    },
  );

  group('ProjectionResolver', () {
    test('returns the loaded model when the log is empty', () async {
      final projection = _Projection<ProjectionEvent>();

      final model = await resolver.resolve(projection);

      expect(model, same(projection.model));
      expect(model.events, isEmpty);
    });

    test('replays matching events after the loaded checkpoint', () async {
      await appendProjectionEvent(store, 'already applied');
      await appendProjectionEvent(store, 'unrelated', path: 'other');
      await appendProjectionEvent(store, 'remaining');
      final projection = _Projection<ProjectionEvent>(
        position: 0,
        filter: const LogFilter.exact('notes/one'),
      );

      final model = await resolver.resolve(projection);

      expect(model.events.single.event.value, 'remaining');
      expect(model.events.single.logPosition, 2);
    });

    test('preserves event envelope metadata', () async {
      await appendProjectionEvent(
        store,
        'value',
        actor: 'remote',
        path: 'notes/two',
        occuredAt: projectionTime,
      );

      final model = await resolver.resolve(_Projection<ProjectionEvent>());

      final event = model.events.single;
      expect(event.event.value, 'value');
      expect(event.actor, 'remote');
      expect(event.streamPath, 'notes/two');
      expect(event.occuredAt, projectionTime);
      expect(event.logPosition, 0);
    });

    test('skips erased events', () async {
      await appendProjectionEvent(
        store,
        '',
        encodedEvent: EncodedEvent.eventErased(),
      );
      await appendProjectionEvent(store, 'retained');

      final model = await resolver.resolve(_Projection<ProjectionEvent>());

      expect(model.events.single.event.value, 'retained');
      expect(model.deletions, isEmpty);
    });

    test('delivers deletion metadata to the model', () async {
      await appendProjectionEvent(
        store,
        '',
        actor: 'remote',
        path: 'notes/deleted',
        encodedEvent: EncodedEvent.streamDeleted(),
      );

      final model = await resolver.resolve(_Projection<ProjectionEvent>());

      final deletion = model.deletions.single;
      expect(deletion.actor, 'remote');
      expect(deletion.streamPath, 'notes/deleted');
      expect(deletion.occuredAt, projectionTime);
      expect(deletion.logPosition, 0);
      expect(model.events, isEmpty);
    });

    test(
      'waits for an asynchronous handler before returning the model',
      () async {
        await appendProjectionEvent(store, 'value');
        final blocked = gate();
        final projection = _Projection<ProjectionEvent>(
          beforeApply: blocked.wait,
        );
        var resolved = false;

        final result = resolver.resolve(projection).then((model) {
          resolved = true;
          return model;
        });
        await blocked.entered.future;
        expect(resolved, isFalse);
        blocked.release();

        expect((await result).events.single.event.value, 'value');
      },
    );

    test('propagates a load failure', () async {
      final error = Exception('load');
      final projection = _Projection<ProjectionEvent>(
        beforeLoad: () => throw error,
      );

      await expectLater(resolver.resolve(projection), throwsA(same(error)));
    });

    test('propagates a handler failure with its stack trace', () async {
      await appendProjectionEvent(store, 'value');
      final error = Exception('apply');
      final trace = StackTrace.current;
      final projection = _Projection<ProjectionEvent>(
        beforeApply: () => Error.throwWithStackTrace(error, trace),
      );

      await _expectFailure(resolver.resolve(projection), error, trace);
    });

    test('rejects a decoded event of the wrong type', () async {
      await appendProjectionEvent(store, 'value');

      await expectLater(
        resolver.resolve(_Projection<String>()),
        throwsStateError,
      );
    });
  });

  group('LiveProjection', () {
    test('loads only after an explicit start', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      final received = <_Model<ProjectionEvent>>[];
      final subscription = live.updates.listen(received.add);
      addTearDown(subscription.cancel);
      await Future<void>(() {});
      expect(projection.loaded, isFalse);
      expect(live.value, isNull);
      expect(received, isEmpty);

      expect(await live.start(), same(projection.model));
      expect(projection.loaded, isTrue);
      expect(live.value, same(projection.model));
    });

    test('repeated starts return the same readiness future', () async {
      final live = create(_Projection<ProjectionEvent>());

      expect(live.start(), same(live.ready));
      expect(live.start(), same(live.ready));
      await live.ready;
      expect(live.start(), same(live.ready));
    });

    test('publishes the initial model only after catch-up', () async {
      await appendProjectionEvent(store, 'existing');
      final live = create(_Projection<ProjectionEvent>());
      final snapshots = live.updates.map(_values).toList();

      await live.start();
      await live.stop();

      expect(await snapshots, [
        ['existing'],
      ]);
    });

    test('resumes live replay after the loaded checkpoint', () async {
      await appendProjectionEvent(store, 'already applied');
      await appendProjectionEvent(store, 'unrelated', path: 'other');
      await appendProjectionEvent(store, 'remaining');
      final live = create(
        _Projection<ProjectionEvent>(
          position: 0,
          filter: const LogFilter.exact('notes/one'),
        ),
      );

      final model = await live.start();

      expect(_values(model), ['remaining']);
      expect(model.events.single.logPosition, 2);
    });

    test('waits for loading before making the model available', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      final blocked = gate();
      projection.beforeLoad = blocked.wait;
      final ready = live.start();
      await blocked.entered.future;

      expect(live.value, isNull);
      await appendProjectionEvent(store, 'during load');
      blocked.release();

      expect(_values(await ready), ['during load']);
    });

    test('readiness includes events notified during replay', () async {
      await appendProjectionEvent(store, 'first');
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      final first = gate();
      final second = gate();
      projection.beforeApply = first.wait;
      var ready = false;
      final completion = live.start().then((_) => ready = true);
      await first.entered.future;

      await appendProjectionEvent(store, 'second');
      projection.beforeApply = second.wait;
      first.release();
      await second.entered.future;
      expect(ready, isFalse);
      expect(live.value, isNull);
      second.release();
      await completion;

      expect(_values(live.value!), ['first', 'second']);
    });

    test('publishes a live update after the handler completes', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      await live.start();
      final blocked = gate();
      projection.beforeApply = blocked.wait;
      final values = <List<String>>[];
      final updated = Completer<void>();
      final subscription = live.updates.listen((model) {
        values.add(_values(model));
        if (model.events.isNotEmpty) updated.complete();
      });
      addTearDown(subscription.cancel);

      await appendProjectionEvent(store, 'new');
      await blocked.entered.future;
      expect(values, [<String>[]]);
      blocked.release();
      await updated.future;

      expect(values, [
        <String>[],
        ['new'],
      ]);
    });

    test('replays the current model to a late listener', () async {
      final live = create(_Projection<ProjectionEvent>());
      await live.start();
      final updated = live.updates.firstWhere(
        (model) => model.events.isNotEmpty,
      );
      await appendProjectionEvent(store, 'new');
      await updated;

      final model = await live.updates.first;

      expect(model, same(live.value));
      expect(_values(model), ['new']);
    });

    test('canceling one listener leaves other listeners active', () async {
      final live = create(_Projection<ProjectionEvent>());
      await live.start();
      final first = live.updates.listen((_) {});
      final second = live.updates.firstWhere(
        (model) => model.events.isNotEmpty,
      );

      await first.cancel();
      await appendProjectionEvent(store, 'new');

      expect(_values(await second), ['new']);
    });

    test('keeps applying events without update listeners', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      await live.start();
      await live.updates.first;
      final applied = Completer<void>();
      projection.afterApply = applied.complete;

      await appendProjectionEvent(store, 'new');
      await applied.future;

      expect(_values(await live.updates.first), ['new']);
    });

    test('publishes deletions after the deletion handler completes', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      await live.start();
      final blocked = gate();
      projection.beforeDeletion = blocked.wait;
      final counts = <int>[];
      final deleted = Completer<void>();
      final subscription = live.updates.listen((model) {
        counts.add(model.deletions.length);
        if (model.deletions.isNotEmpty) deleted.complete();
      });
      addTearDown(subscription.cancel);

      await appendProjectionEvent(
        store,
        '',
        encodedEvent: EncodedEvent.streamDeleted(),
      );
      await blocked.entered.future;
      expect(counts, [0]);
      blocked.release();
      await deleted.future;

      expect(counts, [0, 1]);
      expect(live.value!.deletions.single.streamPath, 'notes/one');
    });

    test('does not publish an update for an erased event', () async {
      final live = create(_Projection<ProjectionEvent>());
      await live.start();
      final values = live.updates.map(_values).toList();
      final updated = live.updates.firstWhere(
        (model) => model.events.isNotEmpty,
      );

      await appendProjectionEvent(
        store,
        '',
        encodedEvent: EncodedEvent.eventErased(),
      );
      await appendProjectionEvent(store, 'retained');
      await updated;
      await live.stop();

      expect(await values, [
        <String>[],
        ['retained'],
      ]);
    });

    test('delivers load failures through ready, updates, and done', () async {
      final error = Exception('load');
      final trace = StackTrace.current;
      final live = create(
        _Projection<ProjectionEvent>(
          beforeLoad: () => Error.throwWithStackTrace(error, trace),
        ),
        failure: same(error),
      );
      final updates = expectLater(
        live.updates,
        emitsInOrder([emitsError(same(error)), emitsDone]),
      );
      final ready = _expectFailure(live.ready, error, trace);
      final done = _expectFailure(live.done, error, trace);

      live.start().ignore();
      await Future.wait([updates, ready, done]);

      expect(live.value, isNull);
      await expectLater(live.ready, throwsA(same(error)));
    });

    test('delivers an initial handler failure before readiness', () async {
      await appendProjectionEvent(store, 'bad');
      final error = Exception('apply');
      final live = create(
        _Projection<ProjectionEvent>(beforeApply: () => throw error),
        failure: same(error),
      );
      final updates = expectLater(
        live.updates,
        emitsInOrder([emitsError(same(error)), emitsDone]),
      );

      await expectLater(live.start(), throwsA(same(error)));
      await updates;
      await expectLater(live.done, throwsA(same(error)));
      expect(live.value, isNull);
    });

    test(
      'delivers a live handler failure without failing completed readiness',
      () async {
        final error = Exception('apply');
        final trace = StackTrace.current;
        final projection = _Projection<ProjectionEvent>();
        final live = create(projection, failure: same(error));
        final model = await live.start();
        projection.beforeApply = () => Error.throwWithStackTrace(error, trace);
        final updates = expectLater(
          live.updates,
          emitsInOrder([same(model), emitsError(same(error)), emitsDone]),
        );
        final done = _expectFailure(live.done, error, trace);

        await appendProjectionEvent(store, 'bad');
        await Future.wait([updates, done]);

        expect(await live.ready, same(model));
      },
    );

    test(
      'delivers a deletion failure without publishing a successful update',
      () async {
        final error = Exception('delete');
        final projection = _Projection<ProjectionEvent>();
        final live = create(projection, failure: same(error));
        final model = await live.start();
        projection.beforeDeletion = () => throw error;
        final updates = expectLater(
          live.updates,
          emitsInOrder([same(model), emitsError(same(error)), emitsDone]),
        );

        await appendProjectionEvent(
          store,
          '',
          encodedEvent: EncodedEvent.streamDeleted(),
        );
        await updates;
        await expectLater(live.done, throwsA(same(error)));
      },
    );

    test(
      'preserves the decoded event type when creating a live projection',
      () async {
        await appendProjectionEvent(store, 'wrong type');
        final live = create(_Projection<String>(), failure: isA<StateError>());

        await expectLater(live.start(), throwsStateError);
        await expectLater(live.done, throwsStateError);
      },
    );

    test('delivers source failures to update listeners', () async {
      final error = Exception('source');
      final trace = StackTrace.current;
      final live = create(_Projection<ProjectionEvent>(), failure: same(error));
      final model = await live.start();
      final updates = expectLater(
        live.updates,
        emitsInOrder([same(model), emitsError(same(error)), emitsDone]),
      );
      final done = _expectFailure(live.done, error, trace);

      store.failNotifications(error, trace);

      await Future.wait([updates, done]);
    });

    test('delivers a terminal failure to late listeners', () async {
      final error = Exception('load');
      final live = create(
        _Projection<ProjectionEvent>(beforeLoad: () => throw error),
        failure: same(error),
      );
      await expectLater(live.start(), throwsA(same(error)));
      await expectLater(live.done, throwsA(same(error)));

      await expectLater(
        live.updates,
        emitsInOrder([emitsError(same(error)), emitsDone]),
      );
    });

    test('stopping before start fails readiness without loading', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);

      await live.stop();

      await expectLater(live.ready, throwsA(isA<ProjectionStoppedException>()));
      await expectLater(live.updates, emitsDone);
      await live.done;
      expect(projection.loaded, isFalse);
      expect(live.start, throwsStateError);
    });

    test('stopping during loading waits for loading to finish', () async {
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      final blocked = gate();
      projection.beforeLoad = blocked.wait;
      live.start().ignore();
      await blocked.entered.future;
      var stopped = false;

      final stopping = live.stop().then((_) => stopped = true);
      await Future<void>(() {});
      expect(stopped, isFalse);
      blocked.release();
      await stopping;

      await expectLater(live.ready, throwsA(isA<ProjectionStoppedException>()));
      expect(live.value, isNull);
    });

    test(
      'stopping during a handler waits and prevents further delivery',
      () async {
        final projection = _Projection<ProjectionEvent>();
        final live = create(projection);
        await live.start();
        final blocked = gate();
        projection.beforeApply = blocked.wait;
        await appendProjectionEvent(store, 'active');
        await blocked.entered.future;
        await appendProjectionEvent(store, 'queued');
        var stopped = false;

        final stopping = live.stop().then((_) => stopped = true);
        await Future<void>(() {});
        expect(stopped, isFalse);
        blocked.release();
        await stopping;

        expect(_values(live.value!), ['active']);
        expect(live.start, throwsStateError);
      },
    );

    test('stopping during initial replay prevents readiness', () async {
      await appendProjectionEvent(store, 'active');
      final projection = _Projection<ProjectionEvent>();
      final live = create(projection);
      final blocked = gate();
      projection.beforeApply = blocked.wait;
      final updates = live.updates.toList();
      live.start().ignore();
      await blocked.entered.future;

      final stopping = live.stop();
      blocked.release();
      await stopping;

      await expectLater(live.ready, throwsA(isA<ProjectionStoppedException>()));
      expect(live.value, isNull);
      expect(await updates, isEmpty);
    });

    test('repeated stops share cleanup', () async {
      final live = create(_Projection<ProjectionEvent>());
      await live.start();

      final stopping = live.stop();
      expect(live.stop(), same(stopping));
      await stopping;
      await live.done;
      await expectLater(
        live.updates,
        emitsInOrder([same(live.value), emitsDone]),
      );
    });

    test('a paused update listener does not prevent stopping', () async {
      final live = create(_Projection<ProjectionEvent>());
      await live.start();
      final subscription = live.updates.listen((_) {});
      addTearDown(subscription.cancel);
      subscription.pause();

      await live.stop();
      await live.done;
    });

    test('source closure closes updates and completes done', () async {
      final live = create(_Projection<ProjectionEvent>());
      final model = await live.start();
      final updates = expectLater(
        live.updates,
        emitsInOrder([same(model), emitsDone]),
      );

      await store.closeChanges();

      await live.done;
      await updates;
    });

    test('source closure before catch-up fails readiness', () async {
      final live = create(
        _Projection<ProjectionEvent>(),
        logPlayer: _ClosedLogPlayer(store),
      );

      await expectLater(
        live.start(),
        throwsA(isA<ProjectionStoppedException>()),
      );
      await live.done;
      await expectLater(live.updates, emitsDone);
      expect(live.value, isNull);
    });
  });
}

List<String> _values(_Model<ProjectionEvent> model) =>
    model.events.map((event) => event.event.value).toList();

Future<void> _expectFailure<T>(
  Future<T> future,
  Object error,
  StackTrace trace,
) => future.then<void>(
  (_) => fail('Expected a failure'),
  onError: (Object actual, StackTrace actualTrace) {
    expect(actual, same(error));
    expect(actualTrace.toString(), trace.toString());
  },
);

class _Model<T extends Object> {
  final events = <EventEnvelope<T>>[];
  final deletions = <StreamDeletion>[];
}

class _Projection<T extends Object> implements Projection<_Model<T>, T> {
  @override
  final LogFilter filter;
  final int position;
  final model = _Model<T>();
  bool loaded = false;
  FutureOr<void> Function()? beforeLoad;
  FutureOr<void> Function()? beforeApply;
  FutureOr<void> Function()? beforeDeletion;
  void Function()? afterApply;

  _Projection({
    this.filter = const LogFilter.all(),
    this.position = -1,
    this.beforeLoad,
    this.beforeApply,
  });

  @override
  String get name => 'test';

  @override
  Future<ProjectionLoad<_Model<T>>> load() async {
    loaded = true;
    await beforeLoad?.call();
    return ProjectionLoad(logPosition: position, model: model);
  }

  @override
  Future<void> apply(_Model<T> model, EventEnvelope<T> envelope) async {
    await beforeApply?.call();
    model.events.add(envelope);
    afterApply?.call();
  }

  @override
  Future<void> onStreamDeleted(_Model<T> model, StreamDeletion deletion) async {
    await beforeDeletion?.call();
    model.deletions.add(deletion);
  }
}

class _ClosedLogPlayer extends LogPlayer {
  _ClosedLogPlayer(super.store);

  @override
  Stream<StoredEvent> followLog(
    LogFilter filter, {
    int fromPosition = 0,
    void Function()? caughtUp,
  }) => const Stream.empty();
}
