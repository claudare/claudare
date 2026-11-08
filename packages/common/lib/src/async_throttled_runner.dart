import 'dart:async';

/// Runs callbacks serially, coalescing requests during each throttle interval.
/// Longer callbacks finish before the next run starts.
final class AsyncThrottledRunner {
  final Future<void> Function() _callback;
  final Duration _delay;

  Future<void>? _activeRun;
  bool _trailingRunRequested = false;

  AsyncThrottledRunner(
    this._callback, {
    Duration delay = const Duration(milliseconds: 200),
  }) : _delay = delay {
    if (delay.isNegative) {
      throw ArgumentError.value(delay, 'delay', 'Must not be negative');
    }
  }

  /// The current run, including throttle waits and trailing work, or null.
  Future<void>? get activeRun => _activeRun;

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
        final delay = Future<void>.delayed(_delay);
        await Future.wait<void>([delay, Future<void>.sync(_callback)]);
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
