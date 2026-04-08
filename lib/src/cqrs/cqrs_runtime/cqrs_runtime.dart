import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/command/command_input.dart';
import 'package:core/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:core/src/cqrs/cqrs_runtime/cqrs_runtime_config.dart';
import 'package:core/src/cqrs/cqrs_runtime/runtime_repo/safe_runtime_repo.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/event_store/event_store_safe.dart';
import 'package:core/src/cqrs/projection/projection_failure_state.dart';
import 'package:core/src/cqrs/projection/projection_router.dart';
import 'package:core/src/cqrs/projection/projection_runtime.dart';
import 'package:core/time_provider.dart';

/// [CqrsRuntime] is all in one place for local CQRS.
/// This class will process commands and ensure that the projections get new events.
class CqrsRuntime {
  late final EventStoreSafe _eventStore;
  late final SafeRuntimeRepo _runtimeRepo;
  late final List<ProjectionRuntime> _projectionRunners;
  final DeviceId _thisDeviceId;
  final String _runtimeName;
  final CqrsRuntimeConfig _config;

  CqrsRuntime({
    required CqrsRuntimeConfig config,
    required DeviceId thisDeviceId,
    required String runtimeName,
    required List<Projection> projectors,
  }) : _runtimeRepo = SafeRuntimeRepo(config.runtimeRepo),
       _runtimeName = runtimeName,
       _thisDeviceId =
           thisDeviceId, // TODO: this needs to be loaded from enrollment
       _config = config {
    _eventStore = EventStoreSafe(config.eventStore);

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

  TimeProvider get timeProvider => _config.timeProvider;
  IdGenerator get idGenerator => _config.idGenerator;

  // Hacky way to force reload.
  // Since runtime repo is involved, this is resilient to restarts
  Future<void> forceReloadAllProjections() async {
    final storedVersion = await _runtimeRepo.getRuntimeVersion(_runtimeName);

    await _runtimeRepo.setRuntimeVersion(_runtimeName, 0);

    await catchupAllProjections(storedVersion);
  }

  Future<void> catchupAllProjections(int currentVersion) async {
    await _runtimeRepo.initialize(); // TODO: get me outa here

    final storedVersion = await _runtimeRepo.getRuntimeVersion(_runtimeName);

    final doReset = currentVersion != storedVersion;

    if (doReset) {
      await Future.wait(
        _projectionRunners.map((runner) => runner.resetProjection()),
      );
    }

    await Future.wait(
      _projectionRunners.map((runner) => runner.catchupSelfLoad(_eventStore)),
    );

    if (doReset) {
      await _runtimeRepo.setRuntimeVersion(_runtimeName, currentVersion);
    }
  }

  Future<void> gracefulShutdown() async {
    // TODO: wait for runners to complete
  }

  BoundCommand<Input> bindCommand<Input extends CommandInput>(
    Command<Input> command,
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

  BoundCommandFn<Input> bindCommand2<Input extends CommandInput>(
    Command<Input> command,
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
    ).runThrowable;
  }
}
