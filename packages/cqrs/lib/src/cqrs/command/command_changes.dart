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
    final streamIds = <String>{};

    for (final event in events) {
      streamIds.add(event.streamId);
    }

    for (final lock in locks) {
      if (!streamIds.remove(lock.streamId)) {
        return false;
      }
    }

    return streamIds.isEmpty;
  }
}

class StreamLocalLock {
  final String streamId;
  final int originatingStreamVersion;

  const StreamLocalLock({
    required this.streamId,
    required this.originatingStreamVersion,
  });
}
