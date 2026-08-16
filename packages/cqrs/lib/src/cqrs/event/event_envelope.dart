import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

// [EventEnvelope] is a container of runtime defined event data.
// It is used in routing of events to projections that match the event's stream ID.
// TODO: rename to RuntimeEvent
class EventEnvelope<Event, IdData> {
  final StreamIdPattern streamIdPattern;
  final String streamIdStr;
  final IdData streamIdData;

  final Event event;
  final DateTime occuredAt;
  final int localSequence;

  const EventEnvelope({
    required this.streamIdStr,
    required this.streamIdData,
    required this.streamIdPattern,
    required this.event,
    required this.occuredAt,
    required this.localSequence,
  });

  @override
  toString() =>
      'EventEnvelope(streamIdStr: $streamIdStr, streamIdData: $streamIdData, streamIdPattern: $streamIdPattern, event: $event, occuredAt: $occuredAt, localSequence: $localSequence)';
}
