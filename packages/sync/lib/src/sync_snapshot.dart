/// Connection state of a coordinator's transport, not replication progress.
enum SyncConnectionState { idle, connecting, connected, reconnecting, closed }

/// Current transport state and admitted replication sessions.
class SyncSnapshot {
  final SyncConnectionState connection;
  final List<String> activePeers;
  final String? lastFailure;

  /// Time of [lastFailure], retained until another failure occurs.
  final DateTime? lastFailureAt;

  SyncSnapshot({
    required this.connection,
    Iterable<String> activePeers = const [],
    this.lastFailure,
    this.lastFailureAt,
  }) : activePeers = List.unmodifiable(activePeers);
}
