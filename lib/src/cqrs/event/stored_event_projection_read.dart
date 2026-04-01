import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';

/// [StoredEventProjectionRead] is for rebuilding projections
class StoredEventProjectionRead {
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  final int localSequence;

  const StoredEventProjectionRead({
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,

    required this.localSequence,
  });

  EventMetadata get eventMetadata =>
      EventMetadata(occuredAt: occuredAt, localSequence: localSequence);
}
