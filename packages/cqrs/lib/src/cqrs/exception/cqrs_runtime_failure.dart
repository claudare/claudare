final class CqrsRuntimeFailure implements Exception {
  final Object error;
  final StackTrace stackTrace;

  const CqrsRuntimeFailure(this.error, this.stackTrace);

  @override
  String toString() => 'CqrsRuntimeFailure: $error';
}
