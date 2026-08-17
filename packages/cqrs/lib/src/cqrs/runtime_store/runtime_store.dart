import 'package:cqrs/src/cqrs/exception/runtime_database_exception.dart';
import 'package:cqrs/src/cqrs/exception/runtime_store_exception.dart';
import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';

class RuntimeStore implements RuntimeStoreProjection {
  final RuntimeDatabase _database;

  const RuntimeStore(this._database);

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
  Future<ProjectionPosition> getProjectionPosition(String name) async {
    final state = await _getProjectionState(name);
    return state?.projectionPosition ?? const ProjectionNotInitialized();
  }

  @override
  Future<void> advanceProjection(
    String name,
    int currentSequence,
    int targetSequence,
    Future<void> Function() action,
  ) async {
    if (currentSequence < 0) {
      throw RuntimeStoreException(
        'Current local sequence must not be negative: $currentSequence',
      );
    }
    if (targetSequence < 0) {
      throw RuntimeStoreException(
        'Target local sequence must not be negative: $targetSequence',
      );
    }
    if (targetSequence <= currentSequence) {
      throw RuntimeStoreException(
        'Target local sequence $targetSequence must be greater than '
        'current local sequence $currentSequence',
      );
    }

    final position = await getProjectionPosition(name);
    if (position is! ProjectionAtSequence ||
        position.scannedThroughLocalSequence != currentSequence) {
      throw RuntimeStoreException(
        "Projection '$name' is not at local sequence $currentSequence",
      );
    }

    await _setProjectionState(
      name,
      RuntimeProjectionState(
        version: position.version,
        applyingThroughLocalSequence: targetSequence,
        scannedThroughLocalSequence: currentSequence,
      ),
    );
    await action();
    await _setProjectionState(
      name,
      RuntimeProjectionState(
        version: position.version,
        applyingThroughLocalSequence: targetSequence,
        scannedThroughLocalSequence: targetSequence,
      ),
    );
  }

  @override
  Future<void> resetProjection(
    String name,
    int version,
    Future<void> Function() action,
  ) async {
    if (version <= 0) {
      throw RuntimeStoreException(
        'Projection version must be positive: $version',
      );
    }

    await _setProjectionState(
      name,
      RuntimeProjectionState(
        version: version,
        applyingThroughLocalSequence: 0,
        scannedThroughLocalSequence: null,
      ),
    );
    await action();
    await _setProjectionState(
      name,
      RuntimeProjectionState(
        version: version,
        applyingThroughLocalSequence: 0,
        scannedThroughLocalSequence: 0,
      ),
    );
  }

  Future<RuntimeProjectionState?> _getProjectionState(String name) async {
    try {
      return await _database.getProjectionState(name);
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to get projection position',
        cause: cause,
      );
    }
  }

  Future<void> _setProjectionState(
    String name,
    RuntimeProjectionState state,
  ) async {
    try {
      await _database.setProjectionState(name, state);
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to set projection position',
        cause: cause,
      );
    }
  }
}
