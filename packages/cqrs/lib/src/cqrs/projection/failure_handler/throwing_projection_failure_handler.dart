import '../projection_failure_handler.dart';

/// [ThrowingProjectionFailureHandler] is useful for tests. Captured exceptions
/// propagate up with their original stack trace.
class ThrowingProjectionFailureHandler implements ProjectionFailureHandler {
  @override
  bool hasErrored() => false;

  @override
  void capture(Exception error, StackTrace stackTrace) {
    Error.throwWithStackTrace(error, stackTrace);
  }
}
