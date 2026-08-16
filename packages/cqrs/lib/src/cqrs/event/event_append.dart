import 'package:cqrs/src/cqrs/event/encoded_event.dart';

/// [EventAppend] is sent as part of a local command append.
class EventAppend {
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const EventAppend({
    required this.streamPath,
    required this.encodedEvent,
    required this.occuredAt,
  });
}
