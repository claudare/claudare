enum EventCodecDirection { encode, decode }

class EventCodecException implements Exception {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final EventCodecDirection direction;
  final String kind;

  const EventCodecException(
    this.message, {
    required this.direction,
    required this.kind,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    return 'EventCodecException{kind: $kind, direction: $direction, message: $message, error: $error}';
  }
}
