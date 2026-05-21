// TODO: Specify where the error happened.
// Is it during init or event application?>
class ProjectionFailureState {
  Object? _error;
  StackTrace? _stackTrace;

  bool get hasError => _error != null;
  Object? get error => _error;
  StackTrace? get stackTrace => _stackTrace;
  String? get message => _error?.toString();

  void capture(Object error, StackTrace stackTrace) {
    assert(_error == null, "dont double throw");
    assert(_stackTrace == null, "dont double throw");

    // only first error will be saved
    _error ??= error;
    _stackTrace ??= stackTrace;

    // TODO: this needs to be available elsewhere.
    // there must be a runtime failure class keeping track of all projection errors.
    // print("PROJECTION ENCOUNTERED AN ERROR: $error; stack trace: $stackTrace");
  }
}
