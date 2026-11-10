import 'dart:async';

import 'package:cqrs/cqrs.dart';

/// Replays and follows events for one projection until stopped.
class ProjectionRunner<TEvent extends Object> {
  final EventRegistry _eventRegistry;
  final LogPlayer _logPlayer;
  final Projection<TEvent> _projection;
  final _doneCompleter = Completer<void>();
  final _readyCompleter = Completer<void>();
  StreamIterator<StoredEvent>? _iterator;
  Future<void>? _iteratorCancellation;
  bool _started = false;
  bool _stopped = false;

  ProjectionRunner(
    this._projection, {
    required this._logPlayer,
    required this._eventRegistry,
  }) {
    // Callers may observe failures through done without awaiting ready.
    _readyCompleter.future.ignore();
  }

  /// Completes after stopping or source closure, or fails after cleanup.
  Future<void> get done => _doneCompleter.future;

  /// Completes on the first catch-up after handling all matching events,
  /// including events notified during replay.
  /// Fails with [ProjectionStoppedException] if stopped before catching up.
  Future<void> get ready => _readyCompleter.future;

  /// Starts once and returns [done]. Starting after [stop] is an error.
  Future<void> start() {
    if (_started) {
      throw StateError('ProjectionRunner already started');
    }
    if (_stopped) {
      throw StateError('ProjectionRunner already stopped');
    }
    _started = true;
    Future<void>(_resolveProjection).then<void>(
      (_) {
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.completeError(const ProjectionStoppedException());
        }
        _doneCompleter.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.completeError(error, stackTrace);
        }
        _doneCompleter.completeError(error, stackTrace);
      },
    );
    return done;
  }

  /// Stops delivery and waits for loading, active handlers, and cleanup.
  /// Repeated calls share cleanup and preserve any run failure.
  Future<void> stop() async {
    _stopped = true;
    if (!_started) {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(const ProjectionStoppedException());
      }
      if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    }
    try {
      await _cancelIterator();
    } finally {
      await done;
    }
  }

  Future<void> _cancelIterator() =>
      _iteratorCancellation ??= _iterator?.cancel() ?? Future<void>.value();

  Future<void> _resolveProjection() async {
    if (_stopped) return;
    final logPosition = await _projection.load();
    if (_stopped) return;

    void markReady() {
      if (!_stopped && !_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }

    final iterator = StreamIterator(
      _logPlayer.followLog(
        _projection.filter,
        fromPosition: logPosition + 1,
        caughtUp: markReady,
      ),
    );
    _iterator = iterator;

    try {
      while (!_stopped && await iterator.moveNext()) {
        if (_stopped) break;
        final logEvent = iterator.current;
        if (logEvent.encodedEvent.isEventErased) {
          continue;
        }
        if (logEvent.encodedEvent.isStreamDeleted) {
          await _projection.onStreamDeleted(
            StreamDeletion(
              actor: logEvent.eventId.actor,
              streamPath: logEvent.streamPath,
              occuredAt: logEvent.occuredAt,
              logPosition: logEvent.position,
            ),
          );
          continue;
        }
        final decoded = _eventRegistry.decode(logEvent.encodedEvent);
        if (decoded is! TEvent) {
          // its programmers job to specify the correct event type
          throw StateError(
            'decoded event is not of type $TEvent: ${decoded.runtimeType}',
          );
        }

        final envelope = EventEnvelope(
          actor: logEvent.eventId.actor,
          streamPath: logEvent.streamPath,
          event: decoded,
          occuredAt: logEvent.occuredAt,
          logPosition: logEvent.position,
        );
        await _projection.apply(envelope);
      }
    } finally {
      await _cancelIterator();
    }
  }
}
