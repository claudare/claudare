import 'package:cqrs/src/cqrs/exception/runtime_database_exception.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';

class RuntimeStore {
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

  Future<int> getRuntimeVersion(String runtimeName) async {
    try {
      final value = await _database.getRuntimeVersion(runtimeName);
      if (value < 0) {
        throw StateError('Invalid runtime version: $value');
      }
      return value;
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to get runtime version',
        cause: cause,
      );
    }
  }

  Future<void> setRuntimeVersion(String runtimeName, int version) async {
    if (version < 0) {
      throw StateError('Invalid runtime version: $version');
    }

    try {
      await _database.setRuntimeVersion(runtimeName, version);
    } on Exception catch (cause) {
      throw RuntimeDatabaseException(
        'Failed to set runtime version',
        cause: cause,
      );
    }
  }
}
