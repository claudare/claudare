import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:common/common.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event_command_read.dart';
import 'package:core/src/cqrs/event/stored_event_command_write.dart';

class GetStreamEventsResult {
  final int originatingStreamVersion; // 0 is no events in this aggregate
  final List<StoredEventCommandRead> events;

  GetStreamEventsResult({
    required this.originatingStreamVersion,
    required this.events,
  });
}

class GetStreamInfoResult {
  /// Used for the dependency tracking
  final DeviceIdSequencePair causalSequencePair;

  /// Used for concurrency check on stream level.
  /// Maybe no-consistency checks will be needed?
  final int originatingStreamVersion;

  const GetStreamInfoResult({
    required this.causalSequencePair,
    required this.originatingStreamVersion,
  });
}

class StreamLocalLock {
  final String streamId;
  final int originatingStreamVersion;

  // could add this flag to skip local consistency checking
  // final bool enforceConsistency;

  const StreamLocalLock({
    required this.streamId,
    required this.originatingStreamVersion,
  });
}

class StreamAppends {
  final EventDependency dependencies;
  final List<StreamLocalLock> localLocks;
  final List<StoredEventCommandWrite> events;

  const StreamAppends({
    required this.dependencies,
    required this.localLocks,
    required this.events,
  });

  StreamAppends.empty()
    : dependencies = EventDependency.empty(),
      localLocks = [],
      events = [];

  /// For assertions, ensures that every inserted event has a lock. This is an internal detail
  /// This behavior may change, to allow lock-free insertion
  bool isValid() {
    final streamIds = <String>{};

    for (final event in events) {
      streamIds.add(event.streamId);
    }

    for (final lock in localLocks) {
      if (!streamIds.remove(lock.streamId)) {
        return false;
      }
    }

    return streamIds.isEmpty;
  }
}

class StreamAppendOrder {
  final int localSequence;

  const StreamAppendOrder({required this.localSequence});
}

class SaveChangesResult {
  final List<StreamAppendOrder> orders;

  const SaveChangesResult({required this.orders});

  SaveChangesResult.empty() : orders = [];
}

abstract interface class EventStoreCommand {
  Future<GetStreamEventsResult> getStreamEvents(
    String streamId,
    int count,
    int streamVersionCursor, // TODO: reorder before count
  );

  /// TODO: I dont like this name + nullable return type
  /// This method must return information on the last event of the stream.
  /// The information is used to lock the stream for appends and to ensure
  /// causal ordering after replication.
  Future<GetStreamInfoResult?> getStreamInfo(String streamId);

  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  );
}
