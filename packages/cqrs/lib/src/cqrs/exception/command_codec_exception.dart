enum CommandCodecDirection { encode, decode }

class CommandCodecException implements Exception {
  final String message;
  final String kind;
  final Object error;
  final StackTrace stackTrace;
  final CommandCodecDirection direction;

  const CommandCodecException(
    this.message, {
    required this.kind,
    required this.error,
    required this.stackTrace,
    required this.direction,
  });

  @override
  String toString() {
    return 'CommandCodecException{kind: $kind, direction: $direction, message: $message, error: $error}';
  }
}
