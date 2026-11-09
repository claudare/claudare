import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/aggregate.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/log_player.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/stream_deletion.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/projection_stopped_exception.dart';
import 'package:cqrs/src/cqrs/projection.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

class ProjectionRun {
  /// Future that completes when projection is cancelled or when event store
  /// closes.
  final Future<void> done;

  /// Completes after processing the matching events present after loading.
  /// Fails with [ProjectionStoppedException] if stopped before catching up.
  /// Replay failures retain their original error.
  final Future<void> ready;

  /// Cancel resolving the projection.
  final Future<void> Function() cancel;

  const ProjectionRun({
    required this.done,
    required this.ready,
    required this.cancel,
  });
}

/// Coordinates durable command execution and projection delivery.
class CqrsRuntime {
  final EventStore _eventStore;
  final String _actor;
  final Logger _logger;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final EventRegistry _eventRegistry = EventRegistry();
  final LogPlayer _logPlayer;

  late final CommandExecutor _commandExecutor;

  CqrsRuntime({
    required this._eventStore,
    required this._actor,
    required this._logger,
    required this._timeProvider,
    required this._idGenerator,
  }) : _logPlayer = LogPlayer(_eventStore) {
    _commandExecutor = CommandExecutor(
      eventStore: _eventStore,
      actor: _actor,
      streamReader: _logPlayer.streamReader,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
      eventRegistry: _eventRegistry,
      logger: _logger,
    );
  }

  String get actor => _actor;

  /// Read and follow events in this runtime's event store.
  ///
  /// For application use only. Other code should use [LogPlayer] directly.
  LogPlayer get logPlayer => _logPlayer;

  EventRegistry get eventRegistry => _eventRegistry;

  Future<void> execute(Command command) {
    return _commandExecutor.execute(command);
  }

  /// Catches up the aggregate to the latest version.
  /// Returns the same [Aggregate] that was passed in.
  Future<Aggregate<TEvent, TState>> resolve<
    TEvent extends Object,
    TState extends AggregateState<TEvent>
  >(Aggregate<TEvent, TState> aggregate) async {
    final startingSequence = aggregate.sequence;
    var applyCount = 0;

    final stream = _logPlayer.logReader(
      aggregate.filter,
      fromPosition: startingSequence + 1,
    );

    await for (final logEvent in stream) {
      if (logEvent.encodedEvent.isEventErased) {
        aggregate.sequence = logEvent.position;
        continue;
      }
      if (logEvent.encodedEvent.isStreamDeleted) {
        aggregate.state.onStreamDeleted(
          StreamDeletion(
            actor: logEvent.eventId.actor,
            streamPath: logEvent.streamPath,
            occuredAt: logEvent.occuredAt,
            logPosition: logEvent.position,
          ),
        );
        aggregate.sequence = logEvent.position;
        continue;
      }
      final decoded = _eventRegistry.decode(logEvent.encodedEvent);
      if (decoded is! TEvent) {
        // its programmers job to specify the correct event type
        throw StateError(
          '$aggregate: decoded event is not of type $TEvent: '
          '${decoded.runtimeType}',
        );
      }

      final envelope = EventEnvelope(
        actor: logEvent.eventId.actor,
        streamPath: logEvent.streamPath,
        event: decoded,
        occuredAt: logEvent.occuredAt,
        logPosition: logEvent.position,
      );
      aggregate.state.apply(envelope);
      _logger.debug(
        '$aggregate: applied event at position ${logEvent.position}',
      );
      aggregate.sequence = logEvent.position;
      applyCount++;
    }

    _logger.debug(
      'resolved $aggregate: '
      'startingSequence=$startingSequence, '
      'finalSequence=${aggregate.sequence}, applyCount=$applyCount',
    );

    return aggregate;
  }

  // Runs the projection until cancelled
  ProjectionRun runProjection<TEvent extends Object>(
    Projection<TEvent> projection,
  ) {
    var cancelled = false;
    StreamIterator<StoredEvent>? it;
    Future<void>? iteratorCancellation;
    final readyCompleter = Completer<void>();
    // Consumers may observe failures through done without awaiting ready.
    readyCompleter.future.ignore();

    Future<void> cancelIterator() =>
        iteratorCancellation ??= it?.cancel() ?? Future<void>.value();

    Future<void> resolveProjection() async {
      if (cancelled) return;
      final logPosition = await projection.load();
      final readyLogPosition = await _eventStore.getLogPosition(
        projection.filter,
      );
      if (cancelled) return;

      void completeIfCaughtUp(int position) {
        if (!cancelled &&
            !readyCompleter.isCompleted &&
            position >= readyLogPosition) {
          readyCompleter.complete();
        }
      }

      completeIfCaughtUp(logPosition);
      final iterator = StreamIterator(
        _logPlayer.followLog(projection.filter, fromPosition: logPosition + 1),
      );
      it = iterator;

      try {
        while (!cancelled && await iterator.moveNext()) {
          if (cancelled) break;
          final logEvent = iterator.current;
          if (logEvent.encodedEvent.isEventErased) {
            completeIfCaughtUp(logEvent.position);
            continue;
          }
          if (logEvent.encodedEvent.isStreamDeleted) {
            await projection.onStreamDeleted(
              StreamDeletion(
                actor: logEvent.eventId.actor,
                streamPath: logEvent.streamPath,
                occuredAt: logEvent.occuredAt,
                logPosition: logEvent.position,
              ),
            );
            completeIfCaughtUp(logEvent.position);
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
          await projection.apply(envelope);
          completeIfCaughtUp(logEvent.position);
        }
      } finally {
        await cancelIterator();
      }
    }

    final done = Future<void>(resolveProjection).then<void>(
      (_) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(const ProjectionStoppedException());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(error, stackTrace);
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );

    return ProjectionRun(
      done: done,
      ready: readyCompleter.future,
      cancel: () async {
        cancelled = true;
        try {
          await cancelIterator();
        } finally {
          await done;
        }
      },
    );
  }
}
