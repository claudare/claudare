class DeviceId implements Comparable<DeviceId> {
  static const int _maxDeviceIdValue = 0xFFFF; // u16

  final int value;

  const DeviceId(this.value)
    : assert(
        value >= 0 && value < _maxDeviceIdValue,
        'incorrect deviceId $value, expected a value in 0-${_maxDeviceIdValue - 1} range',
      );

  /// Creates a DeviceId with zero value. That is how offline mode is
  /// when sync is enabled, ID must be 1...u16
  DeviceId.zero() : value = 0;

  toJson() {
    return value;
  }

  DeviceId.fromJson(int json) : value = json;

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
}
