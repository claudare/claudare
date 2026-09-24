import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/aggregate.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/safe_snapshotter.dart';
import 'package:cqrs/src/cqrs/snapshotter.dart';
import 'package:time_provider/time_provider.dart';

/// Coordinates durable command execution and projection delivery.
class CqrsRuntime {
  final EventStore _eventStore;
  final Logger _logger;
  final TimeProvider _timeProvider;
  final EventRegistry _eventRegistry = EventRegistry();

  late final CommandExecutor _commandExecutor;

  CqrsRuntime({
    required EventStore eventStore,
    required Logger logger,
    required TimeProvider timeProvider,
  }) : _timeProvider = timeProvider,
       _logger = logger,
       _eventStore = eventStore {
    _commandExecutor = CommandExecutor(
      eventStore: _eventStore,
      timeProvider: _timeProvider,
      eventRegistry: _eventRegistry,
      logger: _logger,
    );
  }

  EventRegistry get eventRegistry => _eventRegistry;

  Future<void> execute<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) {
    return _commandExecutor.execute(command, input);
  }

  /// Resolves an aggregate, optionally resuming from its snapshot.
  /// [forceResolveFromEvents] bypasses snapshot loading and saving.
  Future<TState> resolve<TEvent extends Object, TParams, TState>(
    Aggregate<TEvent, TParams, TState> aggregate,
    TParams params, {
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

    final streamPath = aggregate.streamRoute.buildPath(params);

    final stream = _eventStore
        .getLogEventReader((sequence ?? -1) + 1)
        .scan()
        .where((logEvent) {
          // removes irrelevant events as database level filtering is not
          // implemented.
          return aggregate.streamRoute.matches(logEvent.streamPath);
        });

    await for (final logEvent in stream) {
      final decoded = _eventRegistry.decode<TEvent>(logEvent.encodedEvent);
      final envelope = EventEnvelope(
        streamPath: logEvent.streamPath,
        streamParams: aggregate.streamRoute.parseParams(logEvent.streamPath),
        event: decoded,
        occuredAt: logEvent.occuredAt,
      );
      if (!aggregate.canApply(envelope)) continue;

      aggregate.apply(state, envelope);
      sequence = logEvent.logPosition;
      applyCount++;
    }

    if (snapshotter != null &&
        sequence != null &&
        startingSequence != sequence) {
      await snapshotter.save(aggregate.version, Snapshot(state, sequence));
    }

    _logger.info(
      'resolved $streamPath: startingSequence=$startingSequence, finalSequence=$sequence, applyCount=$applyCount',
    );

    return state;
  }
}
