import 'dart:math';

import 'package:core/src/base58.dart';

class Counter16Generator {
  int _value;

  Counter16Generator(this._value)
    : assert(_value >= 0 && _value <= Counter16._maxValue);

  factory Counter16Generator.seeded(int? value) {
    if (value == null) {
      return Counter16Generator(Random.secure().nextInt(Counter16._maxValue));
    }

    return Counter16Generator(value);
  }

  Counter16 next() {
    _value = (_value + 1) % Counter16._maxValue;
    return Counter16(_value);
  }
}

/// 16 bit counter
class Counter16 {
  static const _maxValue = 0xFFFF;
  static const _strLen = 3;

  final int _value;

  const Counter16(this._value) : assert(_value >= 0 && _value <= _maxValue);

  factory Counter16.fromString(String str) {
    if (str.length != _strLen) {
      throw ArgumentError(
        'Bad counter value, should be $_strLen long, got ${str.length} instead',
        str,
      );
    }

    final intValue = Base58.fromString(str);

    return Counter16(intValue);
  }

  int get value => _value;

  @override
  String toString() {
    return Base58.toStringPadded(_value, _strLen);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Counter16) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}
