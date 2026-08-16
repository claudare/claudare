import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';

class MemoryRuntimeDatabase implements RuntimeDatabase {
  final Map<String, int> _runtimeVersions = {};
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<int> getRuntimeVersion(String runtimeName) {
    if (!_initialized) {
      throw StateError('MemoryRuntimeDatabase is not initialized');
    }

    return Future.value(_runtimeVersions[runtimeName] ?? 0);
  }

  @override
  Future<void> setRuntimeVersion(String runtimeName, int version) {
    if (!_initialized) {
      throw StateError('MemoryRuntimeDatabase is not initialized');
    }

    _runtimeVersions[runtimeName] = version;
    return Future.value();
  }
}
