import 'package:core/src/cqrs/command/stored_command.dart';
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
  final int? originatingId; // not needed, as it will be equal to totalCount

  const GetStreamMinimalResult({
    required this.totalCount,
    required this.originatingId,
  });
}

class StreamLock {
  final String streamId;
  final int originatingVersion;

  const StreamLock({required this.streamId, required this.originatingVersion});
}

class StreamAppends {
  final List<StreamLock> locks;
  final List<StoredEventCommandWrite> events; // could be dynamic?

  StreamAppends({required this.locks, required this.events});
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

  Future<void> saveLocalAppends(
    StoredCommandWrite command,
    StreamAppends appends,
  );
}
