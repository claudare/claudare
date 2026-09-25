/// An event store failure with its original cause.
class EventStoreException implements Exception {
  final String message;
  final dynamic cause;

  const EventStoreException(this.message, {this.cause});

  @override
  String toString() => 'EventStoreException: $message';
}
