import 'package:cqrs/src/cqrs/event/encoded_event.dart';

/// [StoredEventCommandWrite] is sent to the event store to write commands
class StoredEventCommandWrite {
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const StoredEventCommandWrite({
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
  });
}
