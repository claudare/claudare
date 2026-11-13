/// Events delivered to projections.
class EventEnvelope<TEvent extends Object> {
  final String actor;
  final String streamPath;
  final TEvent event;
  final DateTime occuredAt;
  final int logPosition;

  const EventEnvelope({
    required this.actor,
    required this.streamPath,
    required this.event,
    required this.occuredAt,
    required this.logPosition,
  });

  @override
  String toString() =>
      'EventEnvelope(actor: $actor, streamPath: $streamPath, '
      'eventType: ${event.runtimeType}, occuredAt: $occuredAt) '
      'logPosition: $logPosition';
}
