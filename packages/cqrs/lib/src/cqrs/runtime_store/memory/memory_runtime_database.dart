import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';

class MemoryRuntimeDatabase implements RuntimeDatabase {
  final Map<String, int> _runtimeVersions = {};
  final Map<String, RuntimeProjectionBoundaries> _projectionBoundaries = {};
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

  @override
  Future<RuntimeProjectionBoundaries?> getProjectionBoundaries(String name) {
    _ensureInitialized();
    return Future.value(_projectionBoundaries[name]);
  }

  @override
  Future<void> setProjectionBoundaries(
    String name, {
    required int? applyingSequence,
    required int? appliedSequence,
  }) {
    _ensureInitialized();
    _projectionBoundaries[name] = RuntimeProjectionBoundaries(
      applyingSequence: applyingSequence,
      appliedSequence: appliedSequence,
    );
    return Future.value();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MemoryRuntimeDatabase is not initialized');
    }
  }
}
