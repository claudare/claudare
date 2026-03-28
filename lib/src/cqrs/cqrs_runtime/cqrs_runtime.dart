import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:core/src/cqrs/cqrs_runtime/cqrs_runtime_config.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_safe.dart';
import 'package:core/src/cqrs/projection/projection_failure_state.dart';
import 'package:core/src/cqrs/projection/projection_router.dart';
import 'package:core/src/cqrs/projection/projection_runtime.dart';
import 'package:core/src/cqrs/projection/projection.dart';

/// [CqrsRuntime] is all in one place for local CQRS.
/// This class will process commands and ensure that the projections get new events.
class CqrsRuntime {
  late final EventStoreSafe _eventStore;
  late final List<ProjectionRuntime> _projectionRunners;
  final DeviceId _thisDeviceId;
  final CqrsRuntimeConfig _config;

  CqrsRuntime({
    required EventStore eventStore,
    required CqrsRuntimeConfig config,
    required DeviceId thisDeviceId,
    required List<Projection> projectors,
  }) : _thisDeviceId = thisDeviceId,
       _config = config {
    _eventStore = EventStoreSafe(eventStore);

    _projectionRunners =
        projectors
            .map(
              (projector) => ProjectionRuntime(
                projector,
                ProjectionFailureState(), // TODO: this needs to be more advanced
                _config.eventStorePageSize,
              ),
            )
            .toList();
  }

  Future<void> init() async {
    // TODO: should this ensure that the event store is initialized too?
    // or is that should be done outside?

    await Future.wait(
      _projectionRunners.map((runner) => runner.catchupSelfLoad(_eventStore)),
    );
  }

  Future<void> gracefulShutdown() async {
    // TODO: wait for runners to complete
    // tell database to shutdown gracefully
  }

  BoundCommand<TInput> bindCommand<TInput>(
    Command<TInput> command,
    List<Projection> consistentProjectors,
  ) {
    final executor = CommandExecutor(
      eventStore: _eventStore,
      timeProvider: _config.timeProvider,
      idGenerator: _config.idGenerator,
      thisDeviceId: _thisDeviceId,
      pageSize: _config.eventStorePageSize,
    );

    final consistentRunners = <ProjectionRuntime>[];
    final eventualRunners = <ProjectionRuntime>[];

    for (final runner in _projectionRunners) {
      final isConsistent = consistentProjectors.any(
        (projector) => runner.isProjection(projector),
      );

      if (isConsistent) {
        consistentRunners.add(runner);
      } else {
        eventualRunners.add(runner);
      }
    }

    return BoundCommand(
      executor: executor,
      command: command,
      consistentRouter: ProjectionRouter(consistentRunners),
      eventualRouter: ProjectionRouter(eventualRunners),
    );
  }
}
