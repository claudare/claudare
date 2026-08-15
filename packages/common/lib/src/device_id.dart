import 'dart:typed_data';

/// A database-local device identifier.
///
/// Zero identifies the current device. Positive values identify other devices
/// and can be assigned incrementally within the local database.
class DeviceId implements Comparable<DeviceId> {
  static const int _maxDeviceIdValue = 0xFFFF; // u16

  final int value;

  factory DeviceId(int value) {
    if (value < 0 || value >= _maxDeviceIdValue) {
      throw FormatException(
        'incorrect deviceId $value, expected a value in 0-${_maxDeviceIdValue - 1} range',
      );
    }
    return DeviceId._(value);
  }

  const DeviceId._(this.value);

  /// Identifies the current device, encoded as zero in its local database.
  const DeviceId.self() : this._(0);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DeviceId) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  int compareTo(DeviceId other) {
    return value.compareTo(other.value);
  }

  bool operator >(DeviceId other) => value > other.value;
  bool operator <(DeviceId other) => value < other.value;
  bool operator >=(DeviceId other) => value >= other.value;
  bool operator <=(DeviceId other) => value <= other.value;

  int toJson() {
    return value;
  }

  factory DeviceId.fromJson(int json) {
    return DeviceId(json);
  }

  Uint8List toBytes() {
    return Uint8List.fromList([value & 0xFF, (value >> 8) & 0xFF]);
  }

  factory DeviceId.fromBytes(Uint8List bytes) {
    return DeviceId(bytes[0] | (bytes[1] << 8));
  }

  @override
  String toString() => 'DeviceId(value: $value)';
}
