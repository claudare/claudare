import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';

class MemoryRuntimeDatabase implements RuntimeDatabase {
  final Map<String, RuntimeProjectionState> _projectionStates = {};
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<RuntimeProjectionState?> getProjectionState(String name) {
    _ensureInitialized();
    return Future.value(_projectionStates[name]);
  }

  @override
  Future<void> setProjectionState(String name, RuntimeProjectionState state) {
    _ensureInitialized();
    _projectionStates[name] = state;
    return Future.value();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception('MemoryRuntimeDatabase is not initialized');
    }
  }
}
