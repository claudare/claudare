class CommandSerializationException implements Exception {
  final String message;
  final Object? error;

  CommandSerializationException(this.message, {this.error});

  @override
  String toString() {
    return 'CommandSerializationException{message: $message, error: $error}';
  }
}
