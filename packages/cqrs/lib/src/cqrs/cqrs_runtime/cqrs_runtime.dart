import 'package:id_generator/id_generator.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/cqrs_runtime_dependencies.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/projection/projection_router.dart';
import 'package:cqrs/src/cqrs/projection/projection_runtime.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store.dart';
import 'package:time_provider/time_provider.dart';

/// [CqrsRuntime] is all in one place for local CQRS.
/// This class will process commands and ensure that the projections get new events.
class CqrsRuntime {
  late final RuntimeStore _runtimeStore;
  late final List<ProjectionRuntime> _projectionRunners;
  final String runtimeName;
  final int runtimeVersion;
  final CqrsRuntimeDependencies _dependencies;

  CqrsRuntime({
    required CqrsRuntimeDependencies dependencies,
    required this.runtimeName,
    required this.runtimeVersion,
    required List<Projection> projectors,
  }) : _runtimeStore = RuntimeStore(dependencies.runtimeDatabase),
       _dependencies = dependencies {
    _projectionRunners =
        projectors
            .map(
              (projector) => ProjectionRuntime(
                projector,
                logger: _dependencies.logger,
                runtimeName: runtimeName,
                runtimeVersion: runtimeVersion,
                runtimeStore: _runtimeStore,
              ),
            )
            .toList();
  }

  TimeProvider get timeProvider => _dependencies.timeProvider;
  IdGenerator get idGenerator => _dependencies.idGenerator;

  // Hacky way to force reload.
  // Since runtime repo is involved, this is resilient to restarts
  Future<void> rerunProjections() async {
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: rerunning all projections',
    );
    await _catchupAllProjections(force: true);
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: reran all projections',
    );
  }

  Future<void> initializeProjections() async {
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: initializing all projections',
    );
    await _catchupAllProjections(force: false);
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: initialized all projections',
    );
  }

  Future<void> _catchupAllProjections({required bool force}) async {
    await _runtimeStore.initialize();

    final storedVersion = await _runtimeStore.getRuntimeVersion(runtimeName);

    final doReset = force || runtimeVersion != storedVersion;

    if (doReset) {
      await Future.wait(
        _projectionRunners.map((runner) {
          _dependencies.logger.debug(
            'runtime $runtimeName@$runtimeVersion: resetting projection: ${runner.projectionName}',
          );
          return runner.resetProjection();
        }),
      );
    }

    await Future.wait(
      _projectionRunners.map((runner) {
        _dependencies.logger.debug(
          'runtime $runtimeName@$runtimeVersion: catching up projection: ${runner.projectionName}',
        );

        return runner.catchupSelfLoad(_dependencies.eventStore);
      }),
    );

    if (doReset) {
      await _runtimeStore.setRuntimeVersion(runtimeName, runtimeVersion);
    }
  }

  BoundCommand<Input> bindCommand<Input extends CommandInput>(
    Command<Input> command,
    List<Projection> consistentProjectors,
  ) {
    final executor = CommandExecutor(
      eventStore: _dependencies.eventStore,
      timeProvider: _dependencies.timeProvider,
      idGenerator: _dependencies.idGenerator,
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
      eventStore: _dependencies.eventStore,
      timeProvider: _dependencies.timeProvider,
      idGenerator: _dependencies.idGenerator,
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
