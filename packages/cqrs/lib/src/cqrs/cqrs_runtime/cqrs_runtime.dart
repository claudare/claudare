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
import 'package:cqrs/src/cqrs/safe_snapshotter.dart';
import 'package:cqrs/src/cqrs/snapshotter.dart';
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
    required EventStore eventStore,
    required String actor,
    required Logger logger,
    required TimeProvider timeProvider,
  }) : _timeProvider = timeProvider,
       _actor = actor,
       _logger = logger,
       _eventStore = eventStore {
    _commandExecutor = CommandExecutor(
      eventStore: _eventStore,
      actor: _actor,
      streamReader: streamReader,
      timeProvider: _timeProvider,
      eventRegistry: _eventRegistry,
      logger: _logger,
    );
  }

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

  /// Resolves an aggregate, optionally resuming from its snapshot.
  /// [forceResolveFromEvents] bypasses snapshot loading and saving.
  Future<TState> resolve<TEvent extends Object, TState>(
    Aggregate<TEvent, TState> aggregate, {
    bool forceResolveFromEvents = false,
  }) async {
    final configuredSnapshotter =
        forceResolveFromEvents ? null : aggregate.snapshotter;
    final snapshotter =
        configuredSnapshotter != null
            ? SafeSnapshotter(configuredSnapshotter, logger: _logger)
            : null;

    TState state;
    int? sequence;

    if (snapshotter != null) {
      final snapshot = await snapshotter.load(aggregate.version);
      if (snapshot != null) {
        state = snapshot.state;
        sequence = snapshot.sequence;
      } else {
        state = aggregate.initialState();
        sequence = null;
      }
    } else {
      state = aggregate.initialState();
      sequence = null;
    }

    final startingSequence = sequence;
    var applyCount = 0;

    final stream = logReader((sequence ?? -1) + 1).scan().where((logEvent) {
      // removes irrelevant events as database level filtering is not
      // implemented.
      return aggregate.streamRoute.matches(logEvent.streamPath);
    });

    await for (final logEvent in stream) {
      final decoded = _eventRegistry.decode<TEvent>(logEvent.encodedEvent);
      final envelope = EventEnvelope(
        actor: logEvent.eventId.actor,
        streamPath: logEvent.streamPath,
        event: decoded,
        occuredAt: logEvent.occuredAt,
      );
      if (!aggregate.canApply(envelope)) continue;

      aggregate.apply(state, envelope);
      sequence = logEvent.position;
      applyCount++;
    }

    if (snapshotter != null &&
        sequence != null &&
        startingSequence != sequence) {
      await snapshotter.save(aggregate.version, Snapshot(state, sequence));
    }

    _logger.info(
      'resolved ${aggregate.streamRoute.pattern}: startingSequence=$startingSequence, finalSequence=$sequence, applyCount=$applyCount',
    );

    return state;
  }
}
