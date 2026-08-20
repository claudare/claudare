import 'dart:async';

import 'package:cqrs/src/cqrs/exception/cqrs_runtime_failure.dart';

enum _CqrsRuntimePhase {
  configuring,
  initializing,
  running,
  failed,
  closing,
  closed,
}

final class CqrsRuntimeLifecycle {
  final StreamController<CqrsRuntimeFailure> _failureController =
      StreamController<CqrsRuntimeFailure>.broadcast(sync: false);

  _CqrsRuntimePhase _phase = _CqrsRuntimePhase.configuring;
  CqrsRuntimeFailure? _failure;

  CqrsRuntimeFailure? get failure => _failure;
  Stream<CqrsRuntimeFailure> get failures => _failureController.stream;
  bool get isInitializing => _phase == _CqrsRuntimePhase.initializing;
  bool get isRunning => _phase == _CqrsRuntimePhase.running;
  bool get isClosed => _phase == _CqrsRuntimePhase.closed;

  void beginInitialization() {
    if (_phase != _CqrsRuntimePhase.configuring) {
      throw StateError('Cannot initialize runtime while it is ${_phase.name}');
    }
    _phase = _CqrsRuntimePhase.initializing;
  }

  void completeInitialization() {
    if (_phase == _CqrsRuntimePhase.initializing) {
      _phase = _CqrsRuntimePhase.running;
    }
  }

  CqrsRuntimeFailure? admitWork(String operation) {
    switch (_phase) {
      case _CqrsRuntimePhase.running:
        return null;
      case _CqrsRuntimePhase.failed:
        return _failure ??
            (throw StateError('Failed runtime has no recorded pump failure'));
      case _CqrsRuntimePhase.configuring ||
          _CqrsRuntimePhase.initializing ||
          _CqrsRuntimePhase.closing ||
          _CqrsRuntimePhase.closed:
        throw StateError('Cannot $operation while runtime is ${_phase.name}');
    }
  }

  CqrsRuntimeFailure recordPumpFailure(Object error, StackTrace stackTrace) {
    final existing = _failure;
    if (existing != null) return existing;

    final failure = CqrsRuntimeFailure(error, stackTrace);
    _failure = failure;
    if (_phase != _CqrsRuntimePhase.closing &&
        _phase != _CqrsRuntimePhase.closed) {
      _phase = _CqrsRuntimePhase.failed;
    }
    _failureController.add(failure);
    return failure;
  }

  void beginClosing() {
    if (_phase == _CqrsRuntimePhase.initializing) {
      throw StateError('Cannot close runtime while it is initializing');
    }
    if (_phase != _CqrsRuntimePhase.closed) {
      _phase = _CqrsRuntimePhase.closing;
    }
  }

  void beginInitializationFailureTeardown() {
    if (_phase != _CqrsRuntimePhase.initializing &&
        _phase != _CqrsRuntimePhase.failed) {
      throw StateError(
        'Cannot tear down failed initialization while runtime is ${_phase.name}',
      );
    }
    _phase = _CqrsRuntimePhase.closing;
  }

  Future<void> completeClosing() async {
    if (_phase == _CqrsRuntimePhase.closed) return;
    await _failureController.close();
    _phase = _CqrsRuntimePhase.closed;
  }
}
