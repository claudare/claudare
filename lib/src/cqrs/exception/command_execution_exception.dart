class CommandExecutionException implements Exception {
  final String message;
  final Exception cause;

  const CommandExecutionException(this.message, {required this.cause});

  @override
  String toString() {
    return 'CommandExecutionException{message: $message, cause: $cause}';
  }
}
