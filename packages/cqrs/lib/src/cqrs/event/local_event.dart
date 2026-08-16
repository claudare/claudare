import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';

/// [LocalEvent] is used for projection processing.
class LocalEvent {
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int localSequence;

  const LocalEvent({
    required this.streamPath,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
  });

  EventMetadata get eventMetadata => EventMetadata(occuredAt: occuredAt);
}
