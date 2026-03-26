enum EventCodecDirection { encode, decode }

class EventCodecException implements Exception {
  final String message;
  final dynamic cause;
  final EventCodecDirection direction;

  EventCodecException(this.message, {required this.direction, this.cause});

  @override
  String toString() {
    return 'EventCodecException{message: $message, cause: $cause, direction: $direction}';
  }
}
