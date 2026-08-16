import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';

/// Sent to save a command and its events atomically while respecting
/// concurrency.
class CommandChanges {
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<StreamLocalLock> locks;
  final List<EventAppend> events;

  const CommandChanges({
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.locks,
    required this.events,
  });

  /// For assertions, ensures that every inserted event has a lock.
  bool isValid() {
    final streamPaths = <String>{};

    for (final event in events) {
      streamPaths.add(event.streamPath);
    }

    for (final lock in locks) {
      if (!streamPaths.remove(lock.streamPath)) {
        return false;
      }
    }

    return streamPaths.isEmpty;
  }
}

class StreamLocalLock {
  final String streamPath;
  final int originatingStreamVersion;

  const StreamLocalLock({
    required this.streamPath,
    required this.originatingStreamVersion,
  });
}
