// import 'package:cqrs/src/cqrs/event/event_id.dart';

/// Events which are emitted to aggregates
class EventEnvelope<TEvent extends Object> {
  final String streamPath;
  final TEvent event;
  final DateTime occuredAt;

  const EventEnvelope({
    required this.streamPath,
    required this.event,
    required this.occuredAt,
  });
}
