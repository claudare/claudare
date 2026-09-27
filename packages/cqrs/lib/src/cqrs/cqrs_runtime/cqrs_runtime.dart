import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/aggregate.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:time_provider/time_provider.dart';

/// Coordinates durable command execution and projection delivery.
class CqrsRuntime {
  final EventStore _eventStore;
  final String _actor;
  final Logger _logger;
  final TimeProvider _timeProvider;
  final EventRegistry _eventRegistry = EventRegistry();

  late final CommandExecutor _commandExecutor;

  CqrsRuntime({
    required this._eventStore,
    required this._actor,
    required this._logger,
    required this._timeProvider,
  }) {
    _commandExecutor = CommandExecutor(
      eventStore: _eventStore,
      actor: _actor,
      streamReader: streamReader,
      timeProvider: _timeProvider,
      eventRegistry: _eventRegistry,
      logger: _logger,
    );
  }

  String get actor => _actor;

  /// Creates a reader starting at the inclusive stream version.
  PaginatedReader<StoredEvent> streamReader(
    String streamPath, {
    int fromVersion = 0,
  }) => PaginatedReader(
    (cursor) => _eventStore.getStreamEvents(streamPath, cursor),
    initialCursor: fromVersion,
  );

  /// Creates a reader starting at the inclusive global log position.
  PaginatedReader<StoredEvent> logReader(int fromPosition) =>
      PaginatedReader(_eventStore.getLogEvents, initialCursor: fromPosition);

  EventRegistry get eventRegistry => _eventRegistry;

  Future<void> execute(Command command) {
    return _commandExecutor.execute(command);
  }

  /// A granular, stateless resolve.
  /// Will start from provided sequence, and return the final sequence.
  Future<int?> resolveStateless<TEvent extends Object>({
    required PatternFilter filter,
    required ApplyEnvelope<TEvent> apply,
    int? sequence,
  }) async {
    final startingSequence = sequence;
    var applyCount = 0;

    final stream = logReader((startingSequence ?? -1) + 1)
        .scan()
        .where((logEvent) {
          // removes irrelevant events as database level filtering is not
          // implemented. In the future, eventStore will support read filtering;
          // with that system in place, this will not be needed.
          return filter.doesMatchPath(logEvent.streamPath);
        });

    await for (final logEvent in stream) {
      final decoded = _eventRegistry.decode(logEvent.encodedEvent);
      if (decoded is! TEvent) {
        // its programmers job to specify the correct event type
        throw StateError(
          'stateless decoded event is not of type $TEvent: ${decoded.runtimeType}',
        );
      }

      final envelope = EventEnvelope(
        actor: logEvent.eventId.actor,
        streamPath: logEvent.streamPath,
        event: decoded,
        occuredAt: logEvent.occuredAt,
      );
      apply(envelope);
      _logger.debug('stateless applied event at position ${logEvent.position}');
      sequence = logEvent.position;
      applyCount++;
    }

    _logger.info(
      'stateless ran on ${filter.path()}: '
      'startingSequence=$startingSequence, finalSequence=$sequence, '
      'applyCount=$applyCount',
    );

    return sequence;
  }

  /// Catches up the aggregate to the latest version.
  /// Returns the same [Aggregate] that was passed in.
  Future<Aggregate<TEvent, TState>> resolve<
    TEvent extends Object,
    TState extends AggregateState<TEvent>
  >(Aggregate<TEvent, TState> aggregate) async {
    final startingSequence = aggregate.sequence;
    var applyCount = 0;

    final stream = logReader((aggregate.sequence ?? -1) + 1)
        .scan()
        .where((logEvent) {
          // removes irrelevant events as database level filtering is not
          // implemented. In the future, eventStore will support read filtering;
          // with that system in place, this will not be needed.
          return aggregate.filter.doesMatchPath(logEvent.streamPath);
        });

    await for (final logEvent in stream) {
      final decoded = _eventRegistry.decode(logEvent.encodedEvent);
      if (decoded is! TEvent) {
        // its programmers job to specify the correct event type
        throw StateError(
          '$aggregate: decoded event is not of type $TEvent: ${decoded.runtimeType}',
        );
      }

      final envelope = EventEnvelope(
        actor: logEvent.eventId.actor,
        streamPath: logEvent.streamPath,
        event: decoded,
        occuredAt: logEvent.occuredAt,
      );

      aggregate.state.apply(envelope);
      _logger.debug(
        '$aggregate: applied event at position ${logEvent.position}',
      );
      aggregate.sequence = logEvent.position;
      applyCount++;
    }

    if (startingSequence == aggregate.sequence) {
      _logger.info(
        'resolved $aggregate: already up to date. sequence=${aggregate.sequence}',
      );
    } else {
      _logger.info(
        'resolved $aggregate: '
        'startingSequence=$startingSequence, finalSequence=${aggregate.sequence}, '
        'applyCount=$applyCount',
      );
    }

    return aggregate;
  }

  /// Observes matching stream change notifications without resolving any state.
  Stream<void> subscribe(PatternFilter filter) => _eventStore.eventChanges
      .where((change) => filter.doesMatchPath(change.stream))
      .map<void>((_) {});
}
