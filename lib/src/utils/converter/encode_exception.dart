class EncodeException implements Exception {
  final String message;
  final Object? error;

  const EncodeException(this.message, {this.error});

  @override
  String toString() {
    return 'EncodeException{message: $message, error: $error}';
  }
}
