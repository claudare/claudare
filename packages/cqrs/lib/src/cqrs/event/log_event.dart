import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';

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
}
