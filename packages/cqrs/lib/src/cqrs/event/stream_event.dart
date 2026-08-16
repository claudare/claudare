import 'package:cqrs/src/cqrs/event/encoded_event.dart';

/// [StreamEvent] is read from a stream during command execution.
class StreamEvent {
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int streamVersion;

  const StreamEvent({
    required this.encodedEvent,
    required this.occuredAt,
    required this.streamVersion,
  });
}
