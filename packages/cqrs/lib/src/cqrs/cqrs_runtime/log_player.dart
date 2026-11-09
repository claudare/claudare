import 'dart:async';

import 'package:cqrs/cqrs.dart';

/// Reads a stream from an inclusive version.
typedef StreamReader = Stream<StoredEvent> Function(
  String streamPath, {
  int fromVersion,
});

typedef LogReader = Stream<StoredEvent> Function(
  LogFilter filter, {
  int fromVersion,
});

/// Replays stored events and observes matching log changes.
class LogPlayer {
  final EventStore _eventStore;

  const LogPlayer(this._eventStore);

  /// Creates a reader starting at the inclusive stream version.
  ///
  /// Includes erased records and stream deletion markers.
  Stream<StoredEvent> streamReader(
    String streamPath, {
    int fromVersion = 0,
  }) async* {
    int? cursor = fromVersion;
    while (cursor != null) {
      final page = await _eventStore.getStreamEvents(streamPath, cursor);
      if (page.data.isEmpty) return;
      for (final event in page.data) {
        yield event;
      }
      cursor = page.next;
    }
  }

  /// Creates a reader starting at the inclusive global log position.
  ///
  /// Includes erased records and stream deletion markers.
  Stream<StoredEvent> logReader(
    LogFilter filter, {
    int fromPosition = 0,
  }) async* {
    int? cursor = fromPosition;
    while (cursor != null) {
      final page = await _eventStore.getLogEvents(filter, cursor);
      if (page.data.isEmpty) return;
      for (final event in page.data) {
        yield event;
      }
      cursor = page.next;
    }
  }

  /// Replays matching records from the inclusive [fromPosition], then follows
  /// changes until the subscription is cancelled or the change stream closes.
  /// Calls [caughtUp] whenever replay reaches the end with no pending changes.
  Stream<StoredEvent> followLog(
    LogFilter filter, {
    int fromPosition = 0,
    void Function()? caughtUp,
  }) {
    var position = fromPosition;
    var pendingChange = false;
    final changes = StreamIterator<void>(
      Stream<void>.multi((controller) {
        void notify() {
          if (pendingChange) return;
          pendingChange = true;
          controller.add(null);
        }

        final subscription = subscribe(filter).listen(
          (_) => notify(),
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
        // Subscribe before the initial replay so concurrent commits are observed.
        notify();
      }),
    );
    final controller = StreamController<StoredEvent>();

    Future<void> replay() async {
      try {
        while (await changes.moveNext()) {
          pendingChange = false;
          await controller.addStream(
            logReader(filter, fromPosition: position).map((event) {
              position = event.position + 1;
              return event;
            }),
            cancelOnError: true,
          );
          if (controller.hasListener && !pendingChange) caughtUp?.call();
        }
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        try {
          await changes.cancel();
        } finally {
          unawaited(controller.close());
        }
      }
    }

    controller.onListen = () => unawaited(replay());
    controller.onCancel = changes.cancel;
    return controller.stream;
  }

  /// Observes matching stream change notifications without resolving any state.
  Stream<void> subscribe(LogFilter filter) => _eventStore.eventChanges
      .where((change) => filter.doesMatchPath(change.stream))
      .map<void>((_) {});
}
