import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';

class GetStreamEventsResult {
  final int originatingVersion; // 0 is no events in this aggregate
  final List<StoredEventCommandRead> events;

  GetStreamEventsResult({
    required this.originatingVersion,
    required this.events,
  });
}

class GetStreamInfoResult {
  /// Used for the dependency tracking
  final DeviceIdSequencePair causalSequencePair;

  /// Used for locking (as all commands are locked for now)
  /// I dont think no consistency check commands are needed?
  final int originatingVersion;

  const GetStreamInfoResult({
    required this.causalSequencePair,
    required this.originatingVersion,
  });
}

class GetStreamInfoPoint {
  final DeviceIdSequencePair causalSequencePair;
  final int localSequence;
  final int version; // if last is gotten, this is the originatingVersion?

  const GetStreamInfoPoint({
    required this.causalSequencePair,
    required this.localSequence,
    required this.version,
  });
}

class StreamLocalLock {
  final String streamId;
  final int originatingVersion;

  const StreamLocalLock({
    required this.streamId,
    required this.originatingVersion,
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
}

class StreamAppendOrder {
  final int localSequence;

  const StreamAppendOrder({required this.localSequence});
}

class StreamAppendResult {
  final List<StreamAppendOrder> orders;

  const StreamAppendResult({required this.orders});

  StreamAppendResult.empty() : orders = [];
}

abstract interface class EventStoreCommand {
  Future<GetStreamEventsResult> getStreamEvents(
    String applicationId,
    String streamId,
    int count,
    int versionCursor,
  );

  /// TODO: I dont like this name + nullable return type
  /// This method must return information on the last event of the stream.
  /// The information is used to lock the stream for appends and to ensure
  /// causal ordering after replication.
  Future<GetStreamInfoResult?> getStreamInfo(
    String applicationId,
    String streamId,
  );

  /// TODO: rename to something better
  Future<StreamAppendResult> multiAppendEvents(
    StoredCommandWrite command,
    StreamAppends appends,
  );
}
