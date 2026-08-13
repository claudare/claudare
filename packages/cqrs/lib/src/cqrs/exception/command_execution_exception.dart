/// TODO: remove me? any kind of command execution issue is just an [Exception]?
class CommandExecutionException implements Exception {
  final String message;
  final Exception cause;

  const CommandExecutionException(this.message, {required this.cause});

  @override
  String toString() {
    return 'CommandExecutionException{message: $message, cause: $cause}';
  }
}
