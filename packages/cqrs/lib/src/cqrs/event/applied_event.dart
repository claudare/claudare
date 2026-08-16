import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';

class AppliedEvent {
  final EventId eventId;
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  // local-only values
  final int localSequence;
  final int streamVersion;

  const AppliedEvent({
    required this.eventId,
    required this.streamPath,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
    required this.streamVersion,
  });

  ReplicatedEvent toReplicatedEvent() => ReplicatedEvent(
    eventId: eventId,
    streamPath: streamPath,
    encodedEvent: encodedEvent,
    occuredAt: occuredAt,
  );

  factory AppliedEvent.fromReplicatedEvent(
    ReplicatedEvent event, {
    required int localSequence,
    required int streamVersion,
  }) => AppliedEvent(
    eventId: event.eventId,
    streamPath: event.streamPath,
    encodedEvent: event.encodedEvent,
    occuredAt: event.occuredAt,
    localSequence: localSequence,
    streamVersion: streamVersion,
  );
}
