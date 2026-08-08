// TODO: this needs a "safe" version
// that will validate the version
abstract interface class RuntimeRepo {
  Future<void> initialize();

  // return 0 when no runtime version is defined
  // this is like application versioning. When new version is released,
  // the value must be increased
  Future<int> getRuntimeVersion(String runtimeName);
  Future<void> setRuntimeVersion(String runtimeName, int version);
}
