enum EventCodecDirection { encode, decode }

class EventCodecException implements Exception {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final EventCodecDirection direction;

  const EventCodecException(
    this.message, {
    required this.direction,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    return 'EventCodecException{message: $message, error: $error, direction: $direction}';
  }
}
