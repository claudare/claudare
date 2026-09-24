import 'dart:async';

import 'package:cqrs/src/cqrs/aggregate.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/cqrs_runtime_dependencies.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/safe_snapshotter.dart';
import 'package:cqrs/src/cqrs/snapshotter.dart';
import 'package:time_provider/time_provider.dart';

/// Coordinates durable command execution and projection delivery.
final class CqrsRuntime {
  final String runtimeName;
  final EventStore eventStore;
  final CqrsRuntimeDependencies _dependencies;
  final EventRegistry _eventRegistry;

  late final CommandExecutor _commandExecutor;

  CqrsRuntime({
    required CqrsRuntimeDependencies dependencies,
    required EventRegistry eventRegistry,
    required this.runtimeName,
  }) : eventStore = EventStore(dependencies.eventDatabase),
       _dependencies = dependencies,
       _eventRegistry = eventRegistry {
    _commandExecutor = CommandExecutor(
      eventStore: eventStore,
      timeProvider: dependencies.timeProvider,
      eventRegistry: _eventRegistry,
      logger: dependencies.logger,
    );
  }

  TimeProvider get timeProvider => _dependencies.timeProvider;

  Future<void> initialize() {
    _eventRegistry.freeze();
    return _initialize();
  }

  Future<void> _initialize() async {
    try {
      await eventStore.migrate();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

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
            ? SafeSnapshotter(
              configuredSnapshotter,
              logger: _dependencies.logger,
            )
            : null;

    TState state;
    int sequence;

    if (snapshotter != null) {
      final snapshot = await snapshotter.load(aggregate.version);
      if (snapshot != null) {
        state = snapshot.state;
        sequence = snapshot.sequence;
      } else {
        state = aggregate.initialState();
        sequence = 0;
      }
    } else {
      state = aggregate.initialState();
      sequence = 0;
    }

    final startingSequence = sequence;
    var applyCount = 0;

    final streamPath = aggregate.streamRoute.buildPath(params);

    final stream = eventStore
        .getAppliedEventReader(sequence)
        .scan()
        .where((local) {
          // removes irrelevant events as database level filtering is not
          // implemented.
          return aggregate.streamRoute.matches(local.streamPath);
        })
        .map((local) {
          final decoded = _eventRegistry.decode<TEvent>(local.encodedEvent);
          return EventEnvelope(
            streamPath: local.streamPath,
            streamParams: aggregate.streamRoute.parseParams(local.streamPath),
            event: decoded,
            occuredAt: local.eventMetadata.occuredAt,
            localSequence: local.localSequence,
            streamVersion: -999,
          );
        })
        .where((envelope) {
          return aggregate.canApply(envelope);
        });

    await for (final envelope in stream) {
      aggregate.apply(state, envelope);
      sequence = envelope.localSequence;
      applyCount++;
    }

    if (snapshotter != null && sequence > 0 && startingSequence != sequence) {
      await snapshotter.save(aggregate.version, Snapshot(state, sequence));
    }

    _dependencies.logger.info(
      'resolved $streamPath: startingSequence=$startingSequence, finalSequence=$sequence, applyCount=$applyCount',
    );

    return state;
  }

  Future<void> close() async {
    try {
      await eventStore.close();
    } catch (_) {
      // swallow errors
    }
  }
}
