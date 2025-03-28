import 'dart:math';

import 'package:core/src/base58.dart';

class DeviceId {
  static const _strLenDevice = 3;
  static const int _maxDeviceIdValue = 0xFFFF; // u16

  final int value; // hmmm, its not bytes

  const DeviceId(this.value)
    : assert(
        value >= 0 && value < _maxDeviceIdValue,
        'incorrect deviceId $value, expected a value in 0-${_maxDeviceIdValue - 1} range',
      );

  /// Creates a DeviceId with a random value
  DeviceId.random() : value = Random.secure().nextInt(_maxDeviceIdValue);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DeviceId) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  /// Creates a [DeviceId] from Base58 string representation
  DeviceId.fromString(String valueStr) : value = Base58.fromString(valueStr) {
    if (value > _maxDeviceIdValue) {
      throw FormatException(
        'invalid deviceId, exceeds maximum allowed value of $_maxDeviceIdValue',
      );
    }
  }

  /// Converts the [DeviceId] to Base58 string representation
  @override
  String toString() => Base58.toStringPadded(value, _strLenDevice);
}
