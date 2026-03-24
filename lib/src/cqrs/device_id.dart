class DeviceId implements Comparable<DeviceId> {
  static const int _maxDeviceIdValue = 0xFFFF; // u16

  final int value;

  const DeviceId(this.value)
    : assert(
        value >= 0 && value < _maxDeviceIdValue,
        'incorrect deviceId $value, expected a value in 0-${_maxDeviceIdValue - 1} range',
      );

  /// Creates a DeviceId with zero value. That means there is no device
  /// equivalent to a "null device".
  DeviceId.zero() : value = 0;

  /// Special kind to unassigned device. When sync is enabled it must be in the
  /// range of  1...u16-1.
  DeviceId.unassigned() : value = 0xFFFF - 1;

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
