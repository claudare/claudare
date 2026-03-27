import 'dart:async';

import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/projection/projection_runtime.dart';

class ProjectionRouter {
  final List<ProjectionRuntime> _runtimes;

  const ProjectionRouter(this._runtimes);

  /// For eventual projection resolution
  void dispatch(Iterable<LiveEventFull> events) {
    if (_runtimes.isEmpty) return;

    for (final event in events) {
      for (final runner in _runtimes) {
        final isAffected = runner.shouldProcess(
          event.streamIdPattern,
          event.streamIdStr,
        );
        if (isAffected) {
          runner.enqueue(event);
        }
      }
    }
  }

  /// For consistent projection resolution.
  /// Waits until the affected projections finish resolving
  Future<void> dispatchAndWait(Iterable<LiveEventFull> events) {
    if (_runtimes.isEmpty) return Future.value();

    final targets = <ProjectionRuntime, int>{};

    // Enqueue immediately, track latest sequence per runner.
    for (final event in events) {
      for (final runner in _runtimes) {
        final isAffected = runner.shouldProcess(
          event.streamIdPattern,
          event.streamIdStr,
        );
        if (!isAffected) continue;

        // the enqueue will use scheduleMicrotask.
        // this is a bit confusing, but elegant.
        // The only way to enqueue and wait without extra memory and
        // iteration
        runner.enqueue(event);
        targets[runner] = event.checkpoint.localSequence;
      }
    }

    if (targets.isEmpty) return Future.value();

    final completer = Completer<void>();
    var remaining = targets.length;
    var done = false;

    void oneDone() {
      if (done) return;
      remaining--;
      if (remaining == 0) {
        done = true;
        completer.complete();
      }
    }

    // Safe if onReached triggers immediately when already reached.
    for (final entry in targets.entries) {
      entry.key.onReached(entry.value, oneDone);
    }

    return completer.future;
  }
}
