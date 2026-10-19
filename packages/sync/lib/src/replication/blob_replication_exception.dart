/// An unexpected request or response in a blob replication session.
class BlobReplicationException implements Exception {
  final String message;

  const BlobReplicationException(this.message);

  @override
  String toString() => 'BlobReplicationException: $message';
}
