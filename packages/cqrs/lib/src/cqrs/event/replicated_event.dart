import 'dart:typed_data';

import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';

class ReplicatedEvent {
  final EventId eventId;
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const ReplicatedEvent({
    required this.eventId,
    required this.streamPath,
    required this.encodedEvent,
    required this.occuredAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is ReplicatedEvent &&
          eventId == other.eventId &&
          streamPath == other.streamPath &&
          encodedEvent.kind == other.encodedEvent.kind &&
          _bytesEqual(encodedEvent.bytes, other.encodedEvent.bytes) &&
          occuredAt == other.occuredAt;

  @override
  int get hashCode => Object.hash(
    eventId,
    streamPath,
    encodedEvent.kind,
    Object.hashAll(encodedEvent.bytes),
    occuredAt,
  );
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
