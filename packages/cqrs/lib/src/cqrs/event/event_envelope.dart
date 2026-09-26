/// Events which are emitted to aggregates
class EventEnvelope<TEvent extends Object> {
  // careful, as this may turn into another TParams spaghetti
  final String actor;
  final String streamPath;
  final TEvent event;
  final DateTime occuredAt;

  const EventEnvelope({
    required this.actor,
    required this.streamPath,
    required this.event,
    required this.occuredAt,
  });

  @override
  String toString() =>
      'EventEnvelope(actor: $actor, streamPath: $streamPath, '
      'eventType: ${event.runtimeType}, occuredAt: $occuredAt)';
}
