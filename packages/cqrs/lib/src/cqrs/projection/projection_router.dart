import 'dart:async';

import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/projection/projection_sink.dart';

class ProjectionRouter {
  final List<ProjectionSink> _runtimes;

  const ProjectionRouter(this._runtimes);

  /// For eventual projection resolution
  void dispatch(Iterable<EventEnvelope> events) {
    if (_runtimes.isEmpty) return;

    for (final event in events) {
      for (final runner in _runtimes) {
        final isAffected = runner.shouldProcess(event.streamPath);
        if (isAffected) {
          runner.enqueue(event);
        }
      }
    }
  }

  /// For consistent projection resolution.
  /// Waits until the affected projections finish resolving
  Future<void> dispatchAndWait(Iterable<EventEnvelope> events) {
    if (_runtimes.isEmpty) return Future.value();

    final completer = Completer<void>();
    var remaining = 1; // sentinel
    var completed = false;

    void oneDone() {
      assert(remaining > 0, 'onDone called more times than registered');
      assert(!completed, 'onDone called after completion');

      if (completed) return;
      remaining--;
      if (remaining == 0) {
        completed = true;
        completer.complete();
      }
    }

    for (final event in events) {
      for (final runner in _runtimes) {
        final isAffected = runner.shouldProcess(event.streamPath);
        if (!isAffected) continue;

        remaining++;
        runner.enqueue(event, onDone: oneDone);
      }
    }

    // Release sentinel after all registrations are done.
    oneDone();

    return completer.future;
  }
}
