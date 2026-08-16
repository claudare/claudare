enum MigrationPolicy { whenVersionChanges, always }

abstract interface class RuntimeStoreRuntimeVersion {
  Future<void> versionMigration(
    String name,
    int targetVersion,
    Future<void> Function() action, {
    MigrationPolicy? policy,
  });
}
