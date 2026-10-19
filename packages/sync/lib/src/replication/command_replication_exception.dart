/// A rejected command or invalid message in a replication session.
class CommandReplicationException implements Exception {
  final String message;

  const CommandReplicationException(this.message);

  @override
  String toString() => 'CommandReplicationException: $message';
}
