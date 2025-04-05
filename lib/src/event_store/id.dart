import 'package:core/src/device_id.dart';
import 'package:core/src/timestamp.dart';
import 'package:messagepack/messagepack.dart';

class EventIdGenerator {
  final DeviceId _deviceId;
  final TimestampGenerator _tsGen;

  EventIdGenerator(this._deviceId) : _tsGen = TimestampGenerator();

  EventId next(Timestamp timestamp) {
    final timestampOrdered = _tsGen.next(timestamp);

    return EventId(timestampOrdered, _deviceId);
  }
}

/// [EventId] is the most common form of an id. Whenever an id for whatever
/// internal logic is needed, this implementation is used
/// it has advantage of always carying the timestamp, but the counter is missing here
/// Stringified it is 11 + 1 + 3 long... 15 chars, rounded up to 16 for storage
class EventId implements Comparable<EventId> {
  final Timestamp timestamp;
  final DeviceId deviceId;

  EventId(this.timestamp, this.deviceId);

  factory EventId.fromString(String str) {
    final parts = str.split('-');
    if (parts.length != 2) {
      throw FormatException('Invalid EventId format', str);
    }
    final timestamp = Timestamp.fromString(parts[0]);
    final deviceId = DeviceId.fromString(parts[1]);

    return EventId(timestamp, deviceId);
  }

  @override
  int compareTo(EventId other) {
    if (timestamp != other.timestamp) {
      return timestamp.compareTo(other.timestamp);
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
    return timestamp == other.timestamp && deviceId == other.deviceId;
  }

  @override
  int get hashCode => timestamp.hashCode ^ deviceId.hashCode;

  void pack(Packer p) {
    timestamp.pack(p);
    deviceId.pack(p);
  }

  // hopefully this is done in a correct order
  EventId.unpack(Unpacker u)
    : timestamp = Timestamp.unpack(u),
      deviceId = DeviceId.unpack(u);

  @override
  String toString() => '$timestamp-$deviceId';
}
