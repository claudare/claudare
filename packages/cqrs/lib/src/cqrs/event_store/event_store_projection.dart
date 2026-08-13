import 'package:cqrs/src/cqrs/event/stored_event_projection_read.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

class GetLocalEventsResult {
  final List<StoredEventProjectionRead> events;
  final int? sequenceNumberCursor; // TODO: this should not be needed...

  const GetLocalEventsResult({
    required this.events,
    required this.sequenceNumberCursor,
  });
}

class GetLocalLastEventResult {
  final int localSequence;

  const GetLocalLastEventResult({required this.localSequence});
}

abstract interface class EventStoreProjection {
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int sequenceNumber,
    int count,
  );
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  );
}
