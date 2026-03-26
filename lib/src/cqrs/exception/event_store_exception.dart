/// A generic event store issue. When anything throws
class EventStoreException implements Exception {
  final String message;
  final dynamic cause;

  EventStoreException(this.message, {this.cause});

  @override
  String toString() => 'EventStoreException: $message';
}
