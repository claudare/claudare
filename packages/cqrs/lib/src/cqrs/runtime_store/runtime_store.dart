import 'package:cqrs/src/cqrs/exception/runtime_database_exception.dart';
import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_runtime_version.dart';

class RuntimeStore
    implements RuntimeStoreProjection, RuntimeStoreRuntimeVersion {
  final RuntimeDatabase _database;
  final MigrationPolicy migrationPolicy;

  const RuntimeStore(
    this._database, {
    this.migrationPolicy = MigrationPolicy.whenVersionChanges,
  });

  Future<void> initialize() async {
    try {
      await _database.initialize();
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to initialize runtime database',
        cause: cause,
      );
    }
  }

  @override
  Future<void> versionMigration(
    String name,
    int targetVersion,
    Future<void> Function() action, {
    MigrationPolicy? policy,
  }) async {
    if (targetVersion <= 0) {
      throw ArgumentError.value(targetVersion, 'targetVersion');
    }

    final storedVersion = await _getRuntimeVersion(name);
    final effectivePolicy = policy ?? migrationPolicy;
    if (effectivePolicy == MigrationPolicy.whenVersionChanges &&
        storedVersion == targetVersion) {
      return;
    }

    await _setRuntimeVersion(name, -1);
    await action();
    await _setRuntimeVersion(name, targetVersion);
  }

  Future<int> _getRuntimeVersion(String name) async {
    try {
      final value = await _database.getRuntimeVersion(name);
      if (value < -1) {
        throw RuntimeDatabaseException(
          'Failed to get runtime version',
          cause: StateError('Invalid runtime version: $value'),
        );
      }
      return value;
    } on RuntimeDatabaseException {
      rethrow;
    } catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to get runtime version',
        cause: cause,
      );
    }
  }

  Future<void> _setRuntimeVersion(String name, int version) async {
    try {
      await _database.setRuntimeVersion(name, version);
    } catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to set runtime version',
        cause: cause,
      );
    }
  }

  @override
  Future<ProjectionPosition> getProjectionPosition(String name) async {
    final boundaries = await _getProjectionBoundaries(name);
    if (boundaries == null) return const ProjectionNotInitialized();

    final applying = boundaries.applyingSequence;
    final applied = boundaries.appliedSequence;
    if (applying == null ||
        applied == null ||
        applying != applied ||
        applying < 0) {
      return const ProjectionInconsistent();
    }
    return ProjectionAtSequence(applying);
  }

  @override
  Future<void> advanceProjection(
    String name,
    int currentSequence,
    int targetSequence,
    Future<void> Function() action,
  ) async {
    if (currentSequence < 0) {
      throw ArgumentError.value(currentSequence, 'currentSequence');
    }
    if (targetSequence < 0) {
      throw ArgumentError.value(targetSequence, 'targetSequence');
    }
    if (targetSequence <= currentSequence) {
      throw ArgumentError.value(
        targetSequence,
        'targetSequence',
        'must be greater than currentSequence',
      );
    }

    final position = await getProjectionPosition(name);
    if (position is! ProjectionAtSequence ||
        position.sequence != currentSequence) {
      throw StateError(
        "Projection '$name' is not at sequence $currentSequence",
      );
    }

    await _setProjectionBoundaries(
      name,
      applyingSequence: targetSequence,
      appliedSequence: currentSequence,
    );
    await action();
    await _setProjectionBoundaries(
      name,
      applyingSequence: targetSequence,
      appliedSequence: targetSequence,
    );
  }

  @override
  Future<void> resetProjection(
    String name,
    Future<void> Function() action,
  ) async {
    await _setProjectionBoundaries(
      name,
      applyingSequence: 0,
      appliedSequence: null,
    );
    await action();
    await _setProjectionBoundaries(
      name,
      applyingSequence: 0,
      appliedSequence: 0,
    );
  }

  Future<RuntimeProjectionBoundaries?> _getProjectionBoundaries(
    String name,
  ) async {
    try {
      return await _database.getProjectionBoundaries(name);
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to get projection position',
        cause: cause,
      );
    }
  }

  Future<void> _setProjectionBoundaries(
    String name, {
    required int? applyingSequence,
    required int? appliedSequence,
  }) async {
    try {
      await _database.setProjectionBoundaries(
        name,
        applyingSequence: applyingSequence,
        appliedSequence: appliedSequence,
      );
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to set projection position',
        cause: cause,
      );
    }
  }
}
