class EventRaw {
  final String kind;
  final Map<String, dynamic> detail;

  const EventRaw(this.kind, this.detail);
}

class EventRawWithMeta extends EventRaw {
  final DateTime createdAt;

  const EventRawWithMeta(super.kind, super.detail, this.createdAt);
}

class GetStreamEventsResult {
  final int? originatingId;
  // cursor is like fromId
  final int? cursorId; // inclusive of the last event below.
  final List<EventRawWithMeta> rawEvents;

  GetStreamEventsResult({
    required this.originatingId,
    required this.cursorId,
    required this.rawEvents,
  });
}

class GetStreamMinimalResult {
  final int totalCount;
  final int? originatingId;

  const GetStreamMinimalResult({
    required this.totalCount,
    required this.originatingId,
  });
}

class StreamAppends {
  final String streamId;
  // when the id is null, this means that this must create a new stream
  // otherwise its a ConcurrencyProblem
  // there is no "zero" AutoincrementId
  final int? originatingId; // version is id in this case
  final List<EventRaw> appendValues; // could be dynamic?

  StreamAppends({
    required this.streamId,
    required this.originatingId,
    required this.appendValues,
  });
}

class AppendLocalEvents {
  final List<StreamAppends> appends;
  final int thisDevice;

  // meta fields go here
  final DateTime now;

  const AppendLocalEvents({
    required this.appends,
    required this.thisDevice,
    required this.now,
  });
}

abstract class EventStore {
  // this should have query-like optionals such as fromVersion (for partial resolving of projections)
  // and till date (to replay events as if they have happened in the past)
  Future<GetStreamEventsResult> getStreamEventsCursor(
    String streamId,
    int count,
    int? versionCursor, // this is a version cursor
  );

  // this could be split into a separate count and originating id
  Future<GetStreamMinimalResult> getStreamMinimal(String streamId);

  Future<void> saveLocalAppends(AppendLocalEvents change);
}
