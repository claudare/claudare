class CommandException implements Exception {
  final String message;

  const CommandException(this.message);

  @override
  String toString() => 'CommandException: $message';
}
