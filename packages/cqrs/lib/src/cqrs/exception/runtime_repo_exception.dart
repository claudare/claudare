class RuntimeRepoException implements Exception {
  final String message;
  final Object? cause;

  const RuntimeRepoException(this.message, {this.cause});

  @override
  String toString() =>
      'RuntimeRepoException: $message. ${cause != null ? 'Cause: $cause' : ''}';
}
