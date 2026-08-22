import 'dart:async';

import 'package:cqrs/src/cqrs/exception/cqrs_runtime_failure.dart';

enum _CqrsRuntimePhase {
  uninitialized,
  initializing,
  rebuilding,
  running,
  failed,
  closing,
  closed,
}

final class CqrsRuntimeLifecycle {
  final StreamController<CqrsRuntimeFailure> _failureController =
      StreamController<CqrsRuntimeFailure>.broadcast(sync: false);

  _CqrsRuntimePhase _phase = _CqrsRuntimePhase.uninitialized;
  CqrsRuntimeFailure? _failure;

  CqrsRuntimeFailure? get failure => _failure;
  Stream<CqrsRuntimeFailure> get failures => _failureController.stream;
  bool get isRunning => _phase == _CqrsRuntimePhase.running;

  void beginInitialization() {
    if (_phase != _CqrsRuntimePhase.uninitialized) {
      throw StateError('Cannot initialize runtime while it is ${_phase.name}');
    }
    _phase = _CqrsRuntimePhase.initializing;
  }

  void beginInitialRebuild() {
    if (_phase != _CqrsRuntimePhase.initializing) {
      throw StateError(
        'Cannot begin initial rebuild while runtime is ${_phase.name}',
      );
    }
    _phase = _CqrsRuntimePhase.rebuilding;
  }

  void beginRebuilding() {
    if (_phase != _CqrsRuntimePhase.running) {
      throw StateError('Cannot rebuild runtime while it is ${_phase.name}');
    }
    _phase = _CqrsRuntimePhase.rebuilding;
  }

  void completeRebuilding() {
    if (_phase == _CqrsRuntimePhase.rebuilding) {
      _phase = _CqrsRuntimePhase.running;
      return;
    }
    if (_phase != _CqrsRuntimePhase.failed) {
      throw StateError(
        'Cannot complete rebuild while runtime is ${_phase.name}',
      );
    }
  }

  CqrsRuntimeFailure? admitWork(String operation) {
    switch (_phase) {
      case _CqrsRuntimePhase.running:
        return null;
      case _CqrsRuntimePhase.failed:
        return _failure ??
            (throw StateError('Failed runtime has no recorded pump failure'));
      case _CqrsRuntimePhase.uninitialized ||
          _CqrsRuntimePhase.initializing ||
          _CqrsRuntimePhase.rebuilding ||
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
    switch (_phase) {
      case _CqrsRuntimePhase.uninitialized ||
          _CqrsRuntimePhase.running ||
          _CqrsRuntimePhase.failed:
        _phase = _CqrsRuntimePhase.closing;
        return;
      case _CqrsRuntimePhase.initializing ||
          _CqrsRuntimePhase.rebuilding ||
          _CqrsRuntimePhase.closing ||
          _CqrsRuntimePhase.closed:
        throw StateError('Cannot close runtime while it is ${_phase.name}');
    }
  }

  void beginInitializationFailureTeardown() {
    if (_phase != _CqrsRuntimePhase.initializing &&
        _phase != _CqrsRuntimePhase.rebuilding &&
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
