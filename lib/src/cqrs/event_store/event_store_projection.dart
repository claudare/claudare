import 'package:core/src/cqrs/event/stored_event_projection_read.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

class GetLocalEventsResult {
  final List<StoredEventProjectionRead> events;
  final int? sequenceNumberCursor; // TODO: this should not be needed...

  const GetLocalEventsResult({
    required this.events,
    required this.sequenceNumberCursor,
  });
}

class GetLocalLastEventResult {
  final int? localSequence;

  const GetLocalLastEventResult({required this.localSequence});
}

abstract interface class EventStoreProjection {
  Future<GetLocalEventsResult> getLocalEvents(
    String applicationId,
    int sequenceNumber,
    PatternFilter patternFilter,
    int count,
  );
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  );
}
