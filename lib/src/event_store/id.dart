import 'package:core/src/device_id.dart';
import 'package:core/src/timestamp.dart';
import 'package:messagepack/messagepack.dart';

class EventIdGenerator {
  int lastTimestamp;
  int lastCounter;
  final DeviceId _deviceId;

  EventIdGenerator(Timestamp timestamp, this.lastCounter, this._deviceId)
    : assert(lastCounter > 0),
      lastTimestamp = timestamp.value;

  EventId next(Timestamp timestamp) {
    final nextCounter = lastCounter++;

    return EventId(timestamp, nextCounter, _deviceId);
  }
}

typedef Sequence = int;

/// [EventId] is the most common form of an id. Whenever an id for whatever
/// internal logic is needed, this implementation is used
/// it has advantage of always carying the timestamp, but the counter is missing here
/// Stringified it is 11 + 1 + 3 long... 15 chars, rounded up to 16 for storage
class EventId implements Comparable<EventId> {
  final Timestamp timestamp; // global autoincrement
  final int sequence; // local autoincrement
  final DeviceId deviceId;

  EventId(this.timestamp, this.sequence, this.deviceId);

  // factory EventId.fromString(String str) {
  //   final parts = str.split('-');
  //   if (parts.length != 2) {
  //     throw FormatException('Invalid EventId format', str);
  //   }
  //   final timestamp = Timestamp.fromString(parts[0]);
  //   final deviceId = DeviceId.fromString(parts[1]);

  //   return EventId(timestamp, deviceId);
  // }

  @override
  int compareTo(EventId other) {
    if (timestamp != other.timestamp) {
      return timestamp.compareTo(other.timestamp);
    }
    if (sequence != other.sequence) {
      return sequence.compareTo(other.sequence);
    }
    return deviceId.compareTo(other.deviceId);
  }

  bool operator >(EventId other) => compareTo(other) > 0;
  bool operator <(EventId other) => compareTo(other) < 0;
  bool operator >=(EventId other) => compareTo(other) >= 0;
  bool operator <=(EventId other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EventId) return false;
    return timestamp == other.timestamp &&
        sequence == other.sequence &&
        deviceId == other.deviceId;
  }

  @override
  int get hashCode =>
      timestamp.hashCode ^ sequence.hashCode ^ deviceId.hashCode;

  void pack(Packer p) {
    timestamp.pack(p);
    p.packInt(sequence);
    deviceId.pack(p);
  }

  // hopefully this is done in a correct order
  EventId.unpack(Unpacker u)
    : timestamp = Timestamp.unpack(u),
      sequence = u.unpackInt()!,
      deviceId = DeviceId.unpack(u);

  @override
  String toString() => '$timestamp-$sequence-$deviceId';
}
