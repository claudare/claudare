import 'dart:async';

final class AsyncTrailingRunner {
  final Future<void> Function() _callback;

  Future<void>? _activeRun;
  bool _trailingRunRequested = false;

  AsyncTrailingRunner(this._callback);

  Future<void> run() {
    final activeRun = _activeRun;
    if (activeRun != null) {
      _trailingRunRequested = true;
      return activeRun;
    }

    final completer = Completer<void>();
    _activeRun = completer.future;
    unawaited(_drain(completer));
    return completer.future;
  }

  Future<void> _drain(Completer<void> completer) async {
    try {
      do {
        _trailingRunRequested = false;
        await _callback();
      } while (_trailingRunRequested);

      _activeRun = null;
      completer.complete();
    } catch (error, stackTrace) {
      _trailingRunRequested = false;
      _activeRun = null;
      completer.completeError(error, stackTrace);
    }
  }
}
