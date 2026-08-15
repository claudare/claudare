import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';

class AppliedEvent {
  final EventId eventId;
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int localSequence;
  final int streamVersion;

  const AppliedEvent({
    required this.eventId,
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
    required this.streamVersion,
  });

  ReplicatedEvent toReplicatedEvent() => ReplicatedEvent(
    eventId: eventId,
    streamId: streamId,
    encodedEvent: encodedEvent,
    occuredAt: occuredAt,
  );

  factory AppliedEvent.fromReplicatedEvent(
    ReplicatedEvent event, {
    required int localSequence,
    required int streamVersion,
  }) => AppliedEvent(
    eventId: event.eventId,
    streamId: event.streamId,
    encodedEvent: event.encodedEvent,
    occuredAt: event.occuredAt,
    localSequence: localSequence,
    streamVersion: streamVersion,
  );
}
