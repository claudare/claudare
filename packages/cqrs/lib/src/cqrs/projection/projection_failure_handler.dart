// universal interface to handle projection failures
abstract interface class ProjectionFailureHandler {
  bool hasErrored();
  void capture(Object error, StackTrace stackTrace);
}
