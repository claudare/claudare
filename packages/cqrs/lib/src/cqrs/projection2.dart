import 'dart:async';

import 'package:cqrs/cqrs.dart' hide Projection;

/// Loaded projection state and its last durably applied log position.
class ProjectionLoad<TModel extends Object> {
  final int logPosition;
  final TModel model;

  const ProjectionLoad({required this.logPosition, required this.model});

  factory ProjectionLoad.initial(TModel model) {
    return ProjectionLoad(logPosition: -1, model: model);
  }
}

/// Loads and updates a mutable read model from matching events.
///
/// State may expose queries backed by a database.
///
/// A projection scoped to one stream can receive its id through constructor.
/// Projections covering multiple streams use [EventEnvelope.streamPath].
///
/// Persistent implementations must commit state changes and their log position
/// atomically, including stream deletions. [load] must return state consistent
/// with that checkpoint. The projection is responsible for version schema checks.
abstract interface class Projection<
  TModel extends Object,
  TEvent extends Object
> {
  String get name;

  LogFilter get filter;

  /// Loads state before replay, returning -1 as the position for fresh state.
  FutureOr<ProjectionLoad<TModel>> load();

  /// Mutates [model] with [envelope].
  FutureOr<void> apply(TModel model, EventEnvelope<TEvent> envelope);

  /// Handles permanent deletion of a matching stream.
  FutureOr<void> onStreamDeleted(TModel model, StreamDeletion deletion);
}

/// Resolves projections once.
class ProjectionResolver {
  final EventRegistry _eventRegistry;
  final LogPlayer _logPlayer;

  new({required this._eventRegistry, required this._logPlayer});

  /// Loads [projection] and replays matching events after its saved position.
  Future<TModel> resolve<TModel extends Object, TEvent extends Object>(
    Projection<TModel, TEvent> projection,
  ) async {
    final loadResult = await projection.load();

    final stream = _logPlayer.logReader(
      projection.filter,
      fromPosition: loadResult.logPosition + 1,
    );

    final model = loadResult.model;
    await for (final logEvent in stream) {
      await _applyLogEvent(projection, model, logEvent, _eventRegistry);
    }
    return model;
  }
}

/// Resolves a projection and keeps its mutable state updated from new events.
///
/// Flutter consumers can use StreamBuilder with [updates] and [value] as initial
/// data. The application owns shared projections; removing a widget cancels its
/// subscription without stopping the projection.
///
/// Application ownership using the proposed runtime factory:
/// ```dart
/// final live = runtime.liveProjection(NoteProjection(noteId));
///
/// // During application initialization.
/// await live.start();
///
/// // During application shutdown.
/// await live.stop();
/// ```
///
/// Updates expose the same mutable state, not historical snapshots. Previously
/// delivered references may change, so identity must not suppress updates.
/// For asynchronous queries, retain a result stream outside the widget's build
/// method and replace it when the query changes:
/// ```dart
/// final results = live.updates.asyncMap(
///   (state) => state.search(query),
/// );
/// ```
/// A frontend controller can coalesce refreshes for expensive queries or
/// frequent updates.
class LiveProjection<TModel extends Object, TEvent extends Object> {
  final Projection<TModel, TEvent> _projection;
  final LogPlayer _logPlayer;
  final EventRegistry _eventRegistry;
  final _ready = Completer<TModel>();
  final _done = Completer<void>();
  final _listeners = <MultiStreamController<TModel>>{};
  TModel? _value;
  StreamIterator<StoredEvent>? _iterator;
  Future<void>? _cancellation;
  Future<void>? _stopping;
  bool _started = false;
  bool _stopped = false;
  bool _finished = false;
  Object? _failure;
  StackTrace? _failureTrace;

  /// Creates an unstarted projection while preserving its event type.
  LiveProjection(
    this._projection, {
    required this._logPlayer,
    required this._eventRegistry,
  }) {
    // Consumers may observe failures through updates, ready, or done.
    _ready.future.ignore();
    _done.future.ignore();
  }

  /// Completes with state after initial catch-up and all matching handlers finish,
  /// including changes notified during replay. Repeated reads share one future.
  ///
  /// Fails on loading or handler failure, or with [ProjectionStoppedException]
  /// if the run stops or the source closes before readiness.
  Future<TModel> get ready => _ready.future;

  /// The ready state, or null until initial catch-up succeeds.
  TModel? get value => _value;

  /// A stable stream supporting multiple listeners.
  ///
  /// Each listener receives the intial ready state. Updates to the value emit
  /// updates.
  ///
  /// Loading and handler failures are delivered as stream errors. The stream
  /// closes after stopping, source closure, or failure. Canceling a listener
  /// does not stop the projection.
  late final Stream<TModel> updates = Stream<TModel>.multi((controller) {
    final model = _value;
    if (model != null) controller.add(model);
    if (_finished) {
      final failure = _failure;
      if (failure != null) controller.addError(failure, _failureTrace);
      controller.close();
      return;
    }
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  }, isBroadcast: true);

  /// Completes after stopping or source closure and cleanup.
  /// Fails with the run failure after cleanup if loading or a handler fails.
  Future<void> get done => _done.future;

  /// Starts once and returns [ready]. Repeated calls return the same future.
  /// Starting after [stop] throws [StateError].
  Future<TModel> start() {
    if (_stopped) throw StateError('LiveProjection already stopped');
    if (!_started) {
      _started = true;
      unawaited(_run());
    }
    return ready;
  }

  /// Stops replay and waits for cleanup.
  /// Repeated calls share cleanup and preserve any run failure.
  Future<void> stop() {
    _stopped = true;
    return _stopping ??= _stop();
  }

  Future<void> _stop() async {
    if (!_started) _finish();
    try {
      await _cancelIterator();
    } finally {
      await done;
    }
  }

  Future<void> _cancelIterator() {
    final iterator = _iterator;
    if (iterator == null) return Future<void>.value();
    return _cancellation ??= iterator.cancel();
  }

  Future<void> _run() async {
    Object? failure;
    StackTrace? trace;
    try {
      await _replay();
    } catch (error, stackTrace) {
      failure = error;
      trace = stackTrace;
    }
    try {
      await _cancelIterator();
    } catch (error, stackTrace) {
      failure ??= error;
      trace ??= stackTrace;
    }
    _finish(failure, trace);
  }

  Future<void> _replay() async {
    final loaded = await _projection.load();
    if (_stopped) return;
    final model = loaded.model;
    final iterator = StreamIterator(
      _logPlayer.followLog(
        _projection.filter,
        fromPosition: loaded.logPosition + 1,
        caughtUp: () {
          if (_stopped || _ready.isCompleted) return;
          _value = model;
          _ready.complete(model);
          _publish(model);
        },
      ),
    );
    _iterator = iterator;
    while (!_stopped && await iterator.moveNext()) {
      if (_stopped) break;
      final applied = await _applyLogEvent(
        _projection,
        model,
        iterator.current,
        _eventRegistry,
      );
      if (applied && !_stopped && _value != null) _publish(model);
    }
  }

  void _publish(TModel model) {
    for (final listener in _listeners) {
      listener.add(model);
    }
  }

  void _finish([Object? failure, StackTrace? trace]) {
    _finished = true;
    _failure = failure;
    _failureTrace = trace;
    if (!_ready.isCompleted) {
      _ready.completeError(
        failure ?? const ProjectionStoppedException(),
        trace,
      );
    }
    for (final listener in _listeners) {
      if (failure != null) listener.addError(failure, trace);
      listener.close();
    }
    _listeners.clear();
    if (failure == null) {
      _done.complete();
    } else {
      _done.completeError(failure, trace);
    }
  }
}

Future<bool> _applyLogEvent<TModel extends Object, TEvent extends Object>(
  Projection<TModel, TEvent> projection,
  TModel model,
  StoredEvent logEvent,
  EventRegistry eventRegistry,
) async {
  if (logEvent.encodedEvent.isEventErased) return false;
  if (logEvent.encodedEvent.isStreamDeleted) {
    await projection.onStreamDeleted(
      model,
      StreamDeletion(
        actor: logEvent.eventId.actor,
        streamPath: logEvent.streamPath,
        occuredAt: logEvent.occuredAt,
        logPosition: logEvent.position,
      ),
    );
    return true;
  }
  final decoded = eventRegistry.decode(logEvent.encodedEvent);
  if (decoded is! TEvent) {
    // its programmers job to specify the correct event type
    throw StateError(
      'decoded event is not of type. want: $TEvent, got: ${decoded.runtimeType}',
    );
  }
  await projection.apply(
    model,
    EventEnvelope(
      actor: logEvent.eventId.actor,
      streamPath: logEvent.streamPath,
      event: decoded,
      occuredAt: logEvent.occuredAt,
      logPosition: logEvent.position,
    ),
  );
  return true;
}
