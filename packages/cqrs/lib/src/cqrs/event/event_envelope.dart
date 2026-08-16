import 'package:cqrs/src/cqrs/event/encoded_event.dart';

// [EventEnvelope] is a container of runtime defined event data.
// It is used in routing of events to projections that match the event's stream path.
// TODO: rename to RuntimeEvent
class EventEnvelope {
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int localSequence;

  const EventEnvelope({
    required this.streamPath,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
  });

  @override
  toString() =>
      'EventEnvelope(streamPath: $streamPath, encodedEvent: $encodedEvent, occuredAt: $occuredAt, localSequence: $localSequence)';
}
