import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

class GetGlobalEventsResult {
  final List<StoredEventProjectionRead> events;
  final int? sequenceNumberCursor;

  const GetGlobalEventsResult({
    required this.events,
    required this.sequenceNumberCursor,
  });
}

abstract interface class EventStoreProjection {
  Future<GetGlobalEventsResult> getGlobalEvents(
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  );
}
