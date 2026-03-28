import 'package:core/src/event_store/id.dart';
import 'package:core/src/timestamp.dart';
import 'package:messagepack/messagepack.dart';

class EventClock implements Comparable<EventClock> {
  final Timestamp timestamp; // global part
  final int sequence; // logical part

  const EventClock(this.timestamp, this.sequence);
  EventClock.fromEventId(EventId eventId)
    : timestamp = eventId.timestamp,
      sequence = eventId.sequence;

  EventClock.zero() : timestamp = Timestamp.zero(), sequence = 0;

  @override
  int compareTo(EventClock other) {
    if (timestamp != other.timestamp) {
      return timestamp.compareTo(other.timestamp);
    }

    return sequence.compareTo(other.sequence);
  }

  void pack(Packer p) {
    timestamp.pack(p);
    p.packInt(sequence);
  }

  EventClock.unpack(Unpacker u)
    : timestamp = Timestamp.unpack(u),
      sequence = u.unpackInt()!;
}
