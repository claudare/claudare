import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

import 'event_store_command.dart';

class EventStoreMock implements EventStoreCommand, EventStoreProjection {
  // --- command
  @override
  Future<GetStreamEventsResult> getStreamEventsCursor(
    String streamId,
    int count,
    int? versionCursor,
  ) {
    // TODO: implement getStreamEventsCursor
    throw UnimplementedError();
  }

  @override
  Future<GetStreamMinimalResult> getStreamInfo(String streamId) {
    // TODO: implement getStreamMinimal
    throw UnimplementedError();
  }

  @override
  Future<StreamAppendResult> multiAppendEvents(
    DeviceId deviceId,
    StoredCommandWrite command,
    StreamAppends appends,
  ) {
    // TODO: implement saveLocalAppends
    throw UnimplementedError();
  }

  // --- projection
  @override
  Future<GetGlobalEventsResult> getGlobalEvents(
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  ) {
    // TODO: implement getGlobalEvents
    throw UnimplementedError();
  }
}
