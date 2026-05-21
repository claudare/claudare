class DecodeException implements Exception {
  final String message;
  final Object? error;

  const DecodeException(this.message, {this.error});

  @override
  String toString() {
    return 'EncodeException{message: $message, error: $error}';
  }
}
