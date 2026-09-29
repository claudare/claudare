/// A rejected command or invalid message in a replication session.
class ReplicationException implements Exception {
  final String message;

  const ReplicationException(this.message);

  @override
  String toString() => 'ReplicationException: $message';
}
