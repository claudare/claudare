import 'package:core/src/cqrs/projection/projection_failure_handler.dart';

class StandardError {
  final Object error;
  final StackTrace stackTrace;

  const StandardError({required this.error, required this.stackTrace});

  @override
  String toString() => 'StandardError(error: $error, stackTrace: $stackTrace)';
}

typedef StandardErrorNotifyFn = void Function(StandardError stdError);

class StandardProjectionFailureHandler implements ProjectionFailureHandler {
  StandardError? _stdError;
  final StandardErrorNotifyFn? _notifyFn;

  StandardProjectionFailureHandler({StandardErrorNotifyFn? notifyFn})
    : _notifyFn = notifyFn;

  StandardError? get error => _stdError;

  @override
  bool hasErrored() => _stdError != null;

  @override
  void capture(Object error, StackTrace stackTrace) {
    if (_stdError != null) {
      throw StateError('StandardProjectionFailureHandler already has an error');
    }

    // only first error will be saved
    _stdError = StandardError(error: error, stackTrace: stackTrace);

    if (_notifyFn != null) _notifyFn(_stdError!);
  }
}
