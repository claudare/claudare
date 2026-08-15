import 'dart:typed_data';

import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';

class ReplicatedEvent {
  final EventId eventId;
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const ReplicatedEvent({
    required this.eventId,
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
  });

  // TODO: make the order of Applied events required to be sorted
  // perform an assertion rather then sorting
  static List<ReplicatedEvent> fromAppliedEvents(
    Iterable<AppliedEvent> events,
  ) {
    final result =
        events.map((event) => event.toReplicatedEvent()).toList()..sort((a, b) {
          final device = a.eventId.deviceId.compareTo(b.eventId.deviceId);
          if (device != 0) return device;
          final sequence = a.eventId.sequence.compareTo(b.eventId.sequence);
          if (sequence != 0) return sequence;
          return a.eventId.index.compareTo(b.eventId.index);
        });
    return List.unmodifiable(result);
  }
}

bool replicatedEventsEqual(ReplicatedEvent a, ReplicatedEvent b) =>
    a.eventId == b.eventId &&
    a.streamId == b.streamId &&
    a.encodedEvent.kind == b.encodedEvent.kind &&
    _bytesEqual(a.encodedEvent.bytes, b.encodedEvent.bytes) &&
    a.occuredAt == b.occuredAt;

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
