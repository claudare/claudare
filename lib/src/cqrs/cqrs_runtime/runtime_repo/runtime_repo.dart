// TODO: this needs a "safe" version
// that will validate the version
abstract interface class RuntimeRepo {
  Future<void> initialize();

  // return 0 when no runtime version is defined
  Future<int> getRuntimeVersion(String runtimeName);
  Future<void> setRuntimeVersion(String runtimeName, int version);
}
