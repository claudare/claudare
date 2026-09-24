import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';

/// [StoredEvent] is an applied event which is used for aggregate replays.
/// It is returned for both local and stream replays.
class StoredEvent {
  final String streamPath;
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int localSequence;
  final int version;

  const StoredEvent({
    required this.streamPath,
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
    required this.version,
  });

  ReplicatedEvent toReplicatedEvent() => ReplicatedEvent(
    eventId: eventId,
    streamPath: streamPath,
    encodedEvent: encodedEvent,
    occuredAt: occuredAt,
  );

  factory StoredEvent.fromReplicatedEvent(
    ReplicatedEvent event, {
    required int localSequence,
    required int streamVersion,
  }) => StoredEvent(
    eventId: event.eventId,
    streamPath: event.streamPath,
    encodedEvent: event.encodedEvent,
    occuredAt: event.occuredAt,
    localSequence: localSequence,
    version: streamVersion,
  );
}
