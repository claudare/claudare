/// Default timing for proxy recovery and peer sessions.
abstract final class SyncDefaults {
  /// Time between failed connection attempts and the deadline for each attempt.
  static const reconnectInterval = Duration(seconds: 10);

  /// Time between peer discovery broadcasts.
  static const discoveryInterval = Duration(seconds: 5);

  /// Time between peer keepalive messages.
  static const keepaliveInterval = Duration(seconds: 5);

  /// Maximum time without receiving a peer session message.
  static const sessionTimeout = Duration(seconds: 15);
}
