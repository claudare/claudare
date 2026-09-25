import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';

/// [StoredEvent] is an event in the log which is used for aggregate replays.
/// It is returned for both log and stream replays.
class StoredEvent {
  final String streamPath;
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int position;
  final int version;

  const StoredEvent({
    required this.streamPath,
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.position,
    required this.version,
  });
}
