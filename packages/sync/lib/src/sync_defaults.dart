/// Default timing for synchronization recovery.
abstract final class SyncDefaults {
  /// Time between failed connection attempts and the deadline for each attempt.
  static const reconnectInterval = Duration(seconds: 10);
}
