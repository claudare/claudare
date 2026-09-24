import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';

/// [LogEvent] is an event in the log which is used for aggregate replays.
/// It is returned for both log and stream replays.
class LogEvent {
  final String streamPath;
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int logPosition;
  final int version;

  const LogEvent({
    required this.streamPath,
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.logPosition,
    required this.version,
  });

  StagedEvent toStagedEvent() => StagedEvent(
    eventId: eventId,
    streamPath: streamPath,
    encodedEvent: encodedEvent,
    occuredAt: occuredAt,
  );

  factory LogEvent.fromStagedEvent(
    StagedEvent event, {
    required int logPosition,
    required int streamVersion,
  }) => LogEvent(
    eventId: event.eventId,
    streamPath: event.streamPath,
    encodedEvent: event.encodedEvent,
    occuredAt: event.occuredAt,
    logPosition: logPosition,
    version: streamVersion,
  );
}
