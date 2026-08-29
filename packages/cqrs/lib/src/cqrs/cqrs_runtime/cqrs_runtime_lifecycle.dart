import 'dart:async';

import 'package:cqrs/src/cqrs/exception/cqrs_projection_failure.dart';

enum _CqrsRuntimePhase {
  uninitialized,
  initializing,
  running,
  failed,
  closing,
  closed,
}

final class CqrsRuntimeLifecycle {
  final StreamController<CqrsProjectionFailure> _failureController =
      StreamController<CqrsProjectionFailure>.broadcast(sync: false);

  _CqrsRuntimePhase _phase = _CqrsRuntimePhase.uninitialized;
  CqrsProjectionFailure? _failure;

  CqrsProjectionFailure? get failure => _failure;
  Stream<CqrsProjectionFailure> get failures => _failureController.stream;
  bool get isRunning => _phase == _CqrsRuntimePhase.running;

  void beginInitialization() {
    if (_phase != _CqrsRuntimePhase.uninitialized) {
      throw StateError('Cannot initialize runtime while it is ${_phase.name}');
    }
    _phase = _CqrsRuntimePhase.initializing;
  }

  void completeInitialization() {
    if (_phase != _CqrsRuntimePhase.initializing) {
      throw StateError(
        'Cannot complete initialization while runtime is ${_phase.name}',
      );
    }
    _phase = _CqrsRuntimePhase.running;
  }

  void beginRecreation() {
    if (_phase != _CqrsRuntimePhase.running) {
      throw StateError(
        'Cannot recreate projections while runtime is ${_phase.name}',
      );
    }
    _phase = _CqrsRuntimePhase.initializing;
  }

  void completeRecreation() {
    if (_phase == _CqrsRuntimePhase.initializing) {
      _phase = _CqrsRuntimePhase.running;
      return;
    }
    if (_phase != _CqrsRuntimePhase.failed) {
      throw StateError(
        'Cannot complete projection recreation while runtime is ${_phase.name}',
      );
    }
  }

  CqrsProjectionFailure? admitWork(String operation) {
    switch (_phase) {
      case _CqrsRuntimePhase.running:
        return null;
      case _CqrsRuntimePhase.failed:
        return _failure ??
            (throw StateError('Failed runtime has no recorded pump failure'));
      case _CqrsRuntimePhase.uninitialized ||
          _CqrsRuntimePhase.initializing ||
          _CqrsRuntimePhase.closing ||
          _CqrsRuntimePhase.closed:
        throw StateError('Cannot $operation while runtime is ${_phase.name}');
    }
  }

  CqrsProjectionFailure recordPumpFailure(CqrsProjectionFailure failure) {
    final existing = _failure;
    if (existing != null) return existing;

    _failure = failure;
    if (_phase != _CqrsRuntimePhase.closing &&
        _phase != _CqrsRuntimePhase.closed) {
      _phase = _CqrsRuntimePhase.failed;
    }
    _failureController.add(failure);
    return failure;
  }

  void beginClosing() {
    switch (_phase) {
      case _CqrsRuntimePhase.uninitialized ||
          _CqrsRuntimePhase.running ||
          _CqrsRuntimePhase.failed:
        _phase = _CqrsRuntimePhase.closing;
        return;
      case _CqrsRuntimePhase.initializing ||
          _CqrsRuntimePhase.closing ||
          _CqrsRuntimePhase.closed:
        throw StateError('Cannot close runtime while it is ${_phase.name}');
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
    if (_phase != _CqrsRuntimePhase.closing) {
      throw StateError(
        'Cannot complete closing while runtime is ${_phase.name}',
      );
    }
    await _failureController.close();
    _phase = _CqrsRuntimePhase.closed;
  }
}
