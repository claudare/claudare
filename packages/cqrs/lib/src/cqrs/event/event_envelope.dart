// import 'package:cqrs/src/cqrs/event/event_id.dart';

/// Events which are emitted to aggregates
class EventEnvelope<TEvent extends Object, TParams> {
  // eventId is technically not needed, but may be useful!
  // final EventId eventId;
  final String streamPath;
  final TParams streamParams;
  final TEvent event;
  final DateTime occuredAt;

  const EventEnvelope({
    // required this.eventId,
    required this.streamPath,
    required this.streamParams,
    required this.event,
    required this.occuredAt,
  });
}
