import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';

/// Sent to save a command and its events atomically while respecting
/// concurrency.
class CommandChanges {
  final VersionVector dependency;
  final DateTime occuredAt;
  final List<StreamLock> locks;
  final List<EventAppend> events;

  const CommandChanges({
    required this.dependency,
    required this.occuredAt,
    required this.locks,
    required this.events,
  });

  /// Whether locks are unique by stream and cover every appended event.
  bool isValid() {
    final lockedStreamPaths = <String>{};

    for (final lock in locks) {
      if (!lockedStreamPaths.add(lock.streamPath)) {
        return false;
      }
    }

    return events.every(
      (event) => lockedStreamPaths.contains(event.streamPath),
    );
  }
}

class StreamLock {
  final String streamPath;
  final int? originatingStreamVersion;

  const StreamLock({
    required this.streamPath,
    required this.originatingStreamVersion,
  });
}
