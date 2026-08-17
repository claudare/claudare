final class RuntimeStoreException implements Exception {
  final String message;

  const RuntimeStoreException(this.message);

  @override
  String toString() => 'RuntimeStoreException: $message';
}
