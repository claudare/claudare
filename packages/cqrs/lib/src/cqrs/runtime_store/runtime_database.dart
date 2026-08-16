abstract interface class RuntimeDatabase {
  Future<void> initialize();

  Future<int> getRuntimeVersion(String runtimeName);
  Future<void> setRuntimeVersion(String runtimeName, int version);
}
