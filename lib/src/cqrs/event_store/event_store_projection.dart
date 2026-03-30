import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

class GetGlobalEventsResult {
  final List<StoredEventProjectionRead> events;
  final int? sequenceNumberCursor; // TODO: this should not be needed...

  const GetGlobalEventsResult({
    required this.events,
    required this.sequenceNumberCursor,
  });
}

abstract interface class EventStoreProjection {
  // TODO: only a single filter per projection
  Future<GetGlobalEventsResult> getGlobalEvents(
    String applicationId,
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  );
}
