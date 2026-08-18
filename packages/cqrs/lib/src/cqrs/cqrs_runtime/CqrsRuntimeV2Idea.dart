// ignore_for_file: file_names

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_codec_safe.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';

class CqrsRuntimeV2Idea {
  final List<ProjectionRuntime> _projections = [];
  final CqrsRuntimeDependencies _dependencies;
  final RuntimeStore _runtimeStore;
  final EventRegistry _eventRegistry = EventRegistry();

  CqrsRuntimeV2Idea(this._dependencies)
    : _runtimeStore = RuntimeStore(_dependencies.runtimeDatabase);

  void registerProjection(Projection projection) {
    final runtime = ProjectionRuntime(
      projection,
      logger: NoopLogger(),
      runtimeName: projection.name,
      runtimeStore: _runtimeStore,
      eventRegistry: _eventRegistry,
    );
    _projections.add(runtime);
  }

  // after running this no more commands or projections can be registered
  // and
  Future<void> initialize() async {
    await _dependencies.eventStore.migrate();
    for (final _ in _projections) {
      // need to make projection runtimes... the version is of the app?
      // all projection catchup code goes here
    }
  }

  Future<void> runCommand<T extends CommandInput>(
    Command<T> command,
    T input,
  ) async {
    final startedAt = _dependencies.timeProvider.now();
    final executionState = CommandExecutionState(locks: [], events: []);

    final context = CommandContext(
      eventStore: _dependencies.eventStore,
      executionState: executionState,
      eventRegistry: _eventRegistry,
      timeProvider: _dependencies.timeProvider,
      idGenerator: _dependencies.idGenerator,
    );

    await command.handle(input, context);

    if (executionState.events.isEmpty) {
      return;
    }

    const commandCodec = CommandCodecSafe();
    final encodedCommand = commandCodec.encode(input);
    final completedAt = _dependencies.timeProvider.now();

    {
      final runtimeEvents =
          await _dependencies.eventStore.saveChanges(
                CommandChanges(
                  encoded: encodedCommand,
                  startedAt: startedAt,
                  completedAt: completedAt,
                  locks: executionState.locks,
                  events: executionState.events as dynamic, // TODO
                ),
              )
              as List<EventEnvelope>; // TODO

      // I think its important this is called right away
      // This is all sync from here on out.
      // Maybe lock the dispatch to be first in line to send?
      // TODO: should there be a mutex in this scope?
      dispatchToProjections(runtimeEvents);
    }

    notifySyncEngineOfNewCommand();
  }

  void dispatchToProjections(List<EventEnvelope> runtimeEvents) {
    for (final event in runtimeEvents) {
      for (final sink in _projections) {
        final isAffected = sink.shouldProcess(event.streamPath);
        if (isAffected) {
          sink.enqueue(event);
        }
      }
    }
  }

  // I think this should be a notification rather then actual data passing in
  // the sync engine can read the [EventStore] on its own and be independed from
  // the runtime
  void notifySyncEngineOfNewCommand() {
    // ladida
  }

  // promote on db level and queue right away
  // hoping that between promotion and application an async boundary
  // did not race condition?? This can be annoying to solve. A mutex is always
  // a simple solution to race conditions
  Future<void> syncEngineNotifiesThatSomeCommandIsReadyForPromotion(
    CommandId commandId,
  ) async {
    // mutex this whole thing
    final appliedEvents =
        await _dependencies.eventStore.promotePendingCommand(commandId)
            as List<AppliedEvent>; // FIXME: the promote returns applied events

    for (final event in appliedEvents) {
      for (final sink in _projections) {
        final isAffected = sink.shouldProcess(event.streamPath);
        if (isAffected) {
          sink.enqueue(event as dynamic);
        }
      }
    }
  }
}

void test2() {}
