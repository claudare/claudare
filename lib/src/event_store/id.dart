import 'package:core/src/device_id.dart';
import 'package:core/src/timestamp.dart';

class EventIdGenerator {
  final DeviceId _deviceId;
  final TimestampGenerator _tsGen;

  EventIdGenerator(this._deviceId) : _tsGen = TimestampGenerator();

  EventId next(Timestamp timestamp) {
    final timestampOrdered = _tsGen.next(timestamp);

    return EventId(timestampOrdered, _deviceId);
  }
}

// id is 11 + 1 + 3 long... 15 chars, rounded up to 16
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
  String toString() => '$timestamp-$deviceId';

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
}
