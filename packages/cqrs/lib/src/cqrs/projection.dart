import 'dart:async';

import 'package:cqrs/cqrs.dart';

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
/// Application ownership using the runtime factory:
/// ```dart
/// final live = runtime.liveProjection(NoteProjection(noteId));
///
/// // During application initialization.
/// await live.latest();
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
  Completer<TModel>? _latest;
  bool _replayRequested = false;
  final _done = Completer<void>();
  final _listeners = <MultiStreamController<TModel>>{};
  StreamSubscription<void>? _changes;
  TModel? _model;
  bool _ready = false;
  int _position = -1;
  bool _stopped = false;
  bool _ended = false;
  bool _finished = false;
  Future<void>? _closing;
  Object? _failure;
  StackTrace? _failureTrace;

  /// Creates an unstarted projection while preserving its event type.
  LiveProjection(
    this._projection, {
    required this._logPlayer,
    required this._eventRegistry,
  }) {
    // Consumers may observe failures through updates, latest, or done.
    _done.future.ignore();
  }

  /// The ready state, or null until initial catch-up succeeds.
  /// Cleared when shutdown completes.
  TModel? get value => _ready ? _model : null;

  /// A stable stream supporting multiple listeners.
  ///
  /// Updates emit a value on every update, including the initial one.
  ///
  /// Loading and handler failures are delivered as stream errors. The stream
  /// closes after stopping, source closure, or failure. Canceling a listener
  /// does not stop the projection.
  late final Stream<TModel> updates = Stream<TModel>.multi((controller) {
    final model = value;
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

  /// Starts lazily and checks the log before returning the latest model.
  /// Concurrent calls share pending replay. Later writes can delay completion.
  /// Throws [StateError] after [stop], and propagates loading or replay failures.
  Future<TModel> latest() {
    if (_stopped) throw StateError('LiveProjection already stopped');
    if (_ended) {
      return Future.error(
        _failure ?? const ProjectionStoppedException(),
        _failureTrace,
      );
    }
    return _requestReplay();
  }

  Future<TModel> _requestReplay() {
    _replayRequested = true;
    final pending = _latest;
    if (pending != null) return pending.future;
    final completion = _latest = Completer<TModel>();
    completion.future.ignore();
    unawaited(_run());
    return completion.future;
  }

  /// Stops replay and waits for active loading or handlers and cleanup.
  /// Repeated calls share cleanup and preserve any run failure.
  Future<void> stop() {
    _stopped = true;
    _end();
    return done;
  }

  void _end([Object? failure, StackTrace? trace]) {
    _failure ??= failure;
    _failureTrace ??= trace;
    _ended = true;
    if (_latest == null) unawaited(_close());
  }

  Future<void> _run() async {
    try {
      if (_model == null) {
        _changes = _logPlayer
            .subscribe(_projection.filter)
            .listen(
              (_) {
                if (!_ended) _requestReplay();
              },
              onError: (Object error, StackTrace trace) => _end(error, trace),
              onDone: _end,
            );
        final loaded = await _projection.load();
        _model = loaded.model;
        _position = loaded.logPosition;
      }
      while (!_ended && _replayRequested) {
        _replayRequested = false;
        await for (final event in _logPlayer.logReader(
          _projection.filter,
          fromPosition: _position + 1,
        )) {
          if (_ended) break;
          final applied = await _applyLogEvent(
            _projection,
            _model!,
            event,
            _eventRegistry,
          );
          _position = event.position;
          if (applied && !_ended && _ready) _publish();
        }
      }
      if (!_ended) {
        final completion = _latest!;
        _latest = null;
        if (!_ready) {
          _ready = true;
          _publish();
        }
        completion.complete(_model!);
      }
    } catch (error, trace) {
      _end(error, trace);
    }
    if (_ended) await _close();
  }

  Future<void> _close() => _closing ??= _finish();

  void _publish() {
    final model = value;
    if (model == null) {
      throw StateError('Attempted to publish without value');
    }

    for (final listener in _listeners) {
      listener.add(model);
    }
  }

  Future<void> _finish() async {
    try {
      await _changes?.cancel();
    } catch (error, trace) {
      _failure ??= error;
      _failureTrace ??= trace;
    }
    _finished = true;
    final failure = _failure;
    final trace = _failureTrace;
    _latest?.completeError(
      failure ?? const ProjectionStoppedException(),
      trace,
    );
    _latest = null;
    for (final listener in _listeners) {
      if (failure != null) listener.addError(failure, trace);
      unawaited(listener.close());
    }
    _listeners.clear();
    _model = null;
    _ready = false;
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
