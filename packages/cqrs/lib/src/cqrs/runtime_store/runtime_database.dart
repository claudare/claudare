abstract interface class RuntimeDatabase {
  Future<void> initialize();

  Future<int> getRuntimeVersion(String runtimeName);
  Future<void> setRuntimeVersion(String runtimeName, int version);

  Future<RuntimeProjectionBoundaries?> getProjectionBoundaries(String name);
  Future<void> setProjectionBoundaries(
    String name, {
    required int? applyingSequence,
    required int? appliedSequence,
  });
}

class RuntimeProjectionBoundaries {
  final int? applyingSequence;
  final int? appliedSequence;

  const RuntimeProjectionBoundaries({
    required this.applyingSequence,
    required this.appliedSequence,
  });
}
