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
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_runtime_version.dart';
import 'package:time_provider/time_provider.dart';

/// [CqrsRuntime] is all in one place for local CQRS.
/// This class will process commands and ensure that the projections get new events.
class CqrsRuntime {
  late final RuntimeStore _runtimeStore;
  late final List<ProjectionRuntime> _projectionRunners;
  final String runtimeName;
  final int runtimeVersion;
  final CqrsRuntimeDependencies _dependencies;
  final EventRegistry _eventRegistry = EventRegistry();

  CqrsRuntime({
    required CqrsRuntimeDependencies dependencies,
    required this.runtimeName,
    required this.runtimeVersion,
    required List<Projection> projections,
    MigrationPolicy migrationPolicy = MigrationPolicy.whenVersionChanges,
  }) : _runtimeStore = RuntimeStore(
         dependencies.runtimeDatabase,
         migrationPolicy: migrationPolicy,
       ),
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
                runtimeVersion: runtimeVersion,
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
      'runtime $runtimeName@$runtimeVersion: recreating all projections',
    );
    await _migrateProjections(policy: MigrationPolicy.always);
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: recreated all projections',
    );
  }

  Future<void> initializeProjections() async {
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: initializing all projections',
    );
    await _migrateProjections();
    _dependencies.logger.info(
      'runtime $runtimeName@$runtimeVersion: initialized all projections',
    );
  }

  Future<void> _migrateProjections({MigrationPolicy? policy}) async {
    await _runtimeStore.initialize();
    var migrated = false;
    await _runtimeStore.versionMigration(runtimeName, runtimeVersion, () async {
      migrated = true;
      await _resetAllProjections();
      await _catchupAllProjections();
    }, policy: policy);
    if (!migrated) {
      await _catchupAllProjections();
    }
  }

  Future<void> _resetAllProjections() async {
    await Future.wait(
      _projectionRunners.map((runner) {
        _dependencies.logger.debug(
          'runtime $runtimeName@$runtimeVersion: resetting projection: ${runner.projectionName}',
        );
        return runner.resetProjection();
      }),
    );
  }

  Future<void> _catchupAllProjections() async {
    await Future.wait(
      _projectionRunners.map((runner) {
        _dependencies.logger.debug(
          'runtime $runtimeName@$runtimeVersion: catching up projection: ${runner.projectionName}',
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
