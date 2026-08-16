class RuntimeDatabaseException implements Exception {
  final String message;
  final Object? cause;

  const RuntimeDatabaseException(this.message, {this.cause});

  @override
  String toString() =>
      'RuntimeDatabaseException: $message. ${cause != null ? 'Cause: $cause' : ''}';
}
