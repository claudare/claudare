/// Default timing for proxy discovery and peer sessions.
abstract final class ProxyTransportDefaults {
  static const _keepaliveSeconds = 30;

  /// Time between peer discovery broadcasts.
  static const discoveryInterval = Duration(seconds: 15);

  /// Time between peer keepalive messages.
  static const keepaliveInterval = Duration(seconds: _keepaliveSeconds);

  /// Maximum peer session inactivity, equal to three keepalive intervals.
  static const sessionTimeout = Duration(seconds: _keepaliveSeconds * 3);
}
