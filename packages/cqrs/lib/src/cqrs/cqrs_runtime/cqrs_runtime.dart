import 'package:id_generator/id_generator.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/bound_command.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/cqrs_runtime_dependencies.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
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
  final CqrsRuntimeDependencies _dependencies;
  final EventRegistry _eventRegistry = EventRegistry();

  CqrsRuntime({
    required CqrsRuntimeDependencies dependencies,
    required this.runtimeName,
    required List<Projection> projections,
  }) : _runtimeStore = RuntimeStore(dependencies.runtimeDatabase),
       _dependencies = dependencies {
    final projectionNames = <String>{};
    for (final projection in projections) {
      if (!projectionNames.add(projection.name)) {
        throw ProjectionConfigurationException(
          'Projection name ${projection.name} is registered more than once',
        );
      }
    }

    _projectionRunners =
        projections
            .map(
              (projector) => ProjectionRuntime(
                projector,
                logger: _dependencies.logger,
                runtimeName: runtimeName,
                runtimeStore: _runtimeStore,
                eventRegistry: _eventRegistry,
              ),
            )
            .toList();
  }

  TimeProvider get timeProvider => _dependencies.timeProvider;
  IdGenerator get idGenerator => _dependencies.idGenerator;

  void registerEvent<T extends Object>(EventCodec<T> codec) {
    _eventRegistry.register(codec);
  }

  Future<void> recreateProjections() async {
    _dependencies.logger.info(
      'runtime $runtimeName: recreating all projections',
    );
    await _runtimeStore.initialize();
    await _resetAllProjections();
    await _catchupAllProjections();
    _dependencies.logger.info(
      'runtime $runtimeName: recreated all projections',
    );
  }

  Future<void> initializeProjections() async {
    _dependencies.logger.info(
      'runtime $runtimeName: initializing all projections',
    );
    await _runtimeStore.initialize();
    await _catchupAllProjections();
    _dependencies.logger.info(
      'runtime $runtimeName: initialized all projections',
    );
  }

  Future<void> _resetAllProjections() async {
    await Future.wait(
      _projectionRunners.map((runner) {
        _dependencies.logger.debug(
          'runtime $runtimeName: resetting projection: ${runner.projectionName}',
        );
        return runner.resetProjection();
      }),
    );
  }

  Future<void> _catchupAllProjections() async {
    await Future.wait(
      _projectionRunners.map((runner) {
        _dependencies.logger.debug(
          'runtime $runtimeName: catching up projection: ${runner.projectionName}',
        );

        return runner.catchupSelfLoad(_dependencies.eventStore);
      }),
    );
  }

  BoundCommand<Input> bindCommand<Input extends CommandInput>(
    Command<Input> command,
    List<Projection> consistentProjections,
  ) {
    final executor = CommandExecutor(
      eventStore: _dependencies.eventStore,
      timeProvider: _dependencies.timeProvider,
      idGenerator: _dependencies.idGenerator,
      eventRegistry: _eventRegistry,
    );

    final consistentRunners = <ProjectionRuntime>[];
    final eventualRunners = <ProjectionRuntime>[];

    for (final runner in _projectionRunners) {
      final isConsistent = consistentProjections.any(
        (projection) => runner.isProjection(projection),
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
