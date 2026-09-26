import 'dart:async';

import 'package:notes/screens/note/note_controller.dart';

/// Runs simulated external edits while this note editor enables them.
class NoteContentSimulation {
  final NoteController controller;
  final Future<void> Function() onPersisted;
  final void Function(Exception) onError;

  Timer? _timer;
  bool _writing = false;
  bool _disposed = false;

  NoteContentSimulation({
    required this.controller,
    required this.onPersisted,
    required this.onError,
  });

  bool get isRunning => _timer != null;

  void start() {
    if (_disposed) throw StateError('Simulation is disposed');
    if (isRunning) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_tick());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _disposed = true;
  }

  Future<void> _tick() async {
    if (_writing || _disposed || !isRunning) return;
    _writing = true;
    try {
      await controller.simulateExternalEdit();
      if (!_disposed) await onPersisted();
    } on Exception catch (error) {
      if (!_disposed) {
        stop();
        onError(error);
      }
    } finally {
      _writing = false;
    }
  }
}
