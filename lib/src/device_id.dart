import 'dart:typed_data';

class DeviceId implements Comparable<DeviceId> {
  static const int _maxDeviceIdValue = 0xFFFF; // u16

  final int value;

  const DeviceId(this.value)
    : assert(
        value >= 0 && value < _maxDeviceIdValue,
        'incorrect deviceId $value, expected a value in 0-${_maxDeviceIdValue - 1} range',
      );

  factory DeviceId.validated(int value) {
    if (value < 0 || value >= _maxDeviceIdValue) {
      throw FormatException(
        'incorrect deviceId $value, expected a value in 0-${_maxDeviceIdValue - 1} range',
      );
    }
    return DeviceId(value);
  }

  /// Creates a DeviceId with zero value. That means there is no device
  /// equivalent to a "null device".
  const DeviceId.zero() : value = 0;

  /// Special kind to unassigned device. Could be used pre-sync in fully offline operation?
  /// When sync is enabled it must be in the range of  1...u16-1.
  const DeviceId.unassigned() : value = 0xFFFF - 1;

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
    return DeviceId.validated(json);
  }

  Uint8List toBytes() {
    return Uint8List.fromList([value & 0xFF, (value >> 8) & 0xFF]);
  }

  factory DeviceId.fromBytes(Uint8List bytes) {
    return DeviceId(bytes[0] | (bytes[1] << 8));
  }

  @override
  String toString() => "DeviceId(value: $value)";
}
