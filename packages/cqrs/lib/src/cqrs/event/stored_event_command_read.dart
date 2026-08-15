import 'package:cqrs/src/cqrs/event/encoded_event.dart';

/// events that are read from event store for the command processing
class StoredEventCommandRead {
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  final int streamVersion;

  const StoredEventCommandRead({
    required this.encodedEvent,
    required this.occuredAt,

    required this.streamVersion,
  });
}
