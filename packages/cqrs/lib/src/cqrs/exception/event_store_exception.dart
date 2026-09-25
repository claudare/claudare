/// An event store failure with its original cause.
/// If stack traces dont show, then we should drop catching these.
class EventStoreException implements Exception {
  final String message;
  final Object? cause;

  const EventStoreException(this.message, {required this.cause});

  @override
  String toString() => 'EventStoreException: $message. Cause: $cause';
}
