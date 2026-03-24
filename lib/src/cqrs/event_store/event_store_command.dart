import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/stored_event.dart';

class GetStreamEventsResult {
  final int originatingVersion; // 0 is no events in this aggregate
  final int? versionCursor; // inclusive of the last event. For pagination
  final List<StoredEventCommandRead> events;

  GetStreamEventsResult({
    required this.originatingVersion,
    required this.versionCursor,
    required this.events,
  });
}

class GetStreamMinimalResult {
  final int totalCount;
  final int originatingVersion; // not needed, as it will be equal to totalCount

  const GetStreamMinimalResult({
    required this.totalCount,
    required this.originatingVersion,
  });
}

class StreamLock {
  final String streamIdStr;
  final int originatingVersion;

  const StreamLock({
    required this.streamIdStr,
    required this.originatingVersion,
  });
}

class StreamAppends {
  final List<StreamLock> locks;
  final List<StoredEventCommandWrite> events; // could be dynamic?

  StreamAppends({required this.locks, required this.events});
}

class StreamAppendOrder {
  final int localSequence;
  final int version; // useless?

  const StreamAppendOrder({required this.localSequence, required this.version});
}

class StreamAppendResult {
  final List<StreamAppendOrder> orders;

  const StreamAppendResult({required this.orders});
}

abstract class EventStoreCommand {
  // this should have query-like optionals such as fromVersion (for partial resolving of projections)
  // and till date (to replay events as if they have happened in the past)
  Future<GetStreamEventsResult> getStreamEventsCursor(
    String streamId,
    int count,
    int? versionCursor, // this is a version cursor
  );

  // this could be split into a separate count and originating id
  Future<GetStreamMinimalResult> getStreamMinimal(String streamId);

  // This is a local command insertion
  // deviceId should be passed here either in the write or as a parameter
  // the database should have no idea whats its deviceId
  Future<StreamAppendResult> multiAppendEvents(
    DeviceId thisDeviceId,
    StoredCommandWrite command,
    StreamAppends appends,
  );
}
