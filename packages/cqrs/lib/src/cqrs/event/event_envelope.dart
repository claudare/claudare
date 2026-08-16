// [EventEnvelope] is a container of runtime defined event data.
// It is used in routing of events to projections that match the event's stream path.
// TODO: rename to RuntimeEvent
class EventEnvelope<Event, Params> {
  final String streamPath;
  final Params streamParams;

  final Event event;
  final DateTime occuredAt;
  final int localSequence;

  const EventEnvelope({
    required this.streamPath,
    required this.streamParams,
    required this.event,
    required this.occuredAt,
    required this.localSequence,
  });

  @override
  toString() =>
      'EventEnvelope(streamPath: $streamPath, streamParams: $streamParams, event: $event, occuredAt: $occuredAt, localSequence: $localSequence)';
}
