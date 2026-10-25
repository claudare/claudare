/// Default timing for synchronization recovery and blob retries.
abstract final class SyncDefaults {
  /// Time between failed connection attempts and the deadline for each attempt.
  static const reconnectInterval = Duration(seconds: 10);

  /// Time between completed pending-blob scans and retries from zero.
  static const blobRetryInterval = Duration(seconds: 10);
}
