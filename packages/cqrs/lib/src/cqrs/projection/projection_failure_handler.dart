// universal interface to handle projection failures
abstract interface class ProjectionFailureHandler {
  bool hasErrored();
  void capture(Exception error, StackTrace stackTrace);
}
