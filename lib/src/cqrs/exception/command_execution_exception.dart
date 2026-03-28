class CommandExecutionException implements Exception {
  final String message;
  final Exception? cause;

  CommandExecutionException(this.message, {this.cause});

  @override
  String toString() {
    return 'CommandExecutionException{message: $message, cause: $cause}';
  }
}
