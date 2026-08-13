import '../projection_failure_handler.dart';

/// [ThrowingProjectionFailureHandler] is useful for tests. Any kind of failure propagates up.
class ThrowingProjectionFailureHandler implements ProjectionFailureHandler {
  @override
  bool hasErrored() => false;

  @override
  void capture(Object error, StackTrace stackTrace) {
    Error.throwWithStackTrace(error, stackTrace);
  }
}
