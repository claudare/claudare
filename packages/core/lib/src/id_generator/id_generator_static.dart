import 'dart:typed_data';

import 'package:core/src/id_generator/id_generator.dart';

class IdGeneratorStatic implements IdGenerator {
  late int _value;

  IdGeneratorStatic(int value) {
    set(value);
  }

  void set(int value) {
    if (value < 0 || value.bitLength > IdGenerator.byteLength * 8) {
      throw RangeError.value(value, 'value', 'Must fit in 128 unsigned bits');
    }
    _value = value;
  }

  @override
  Uint8List generateBytes() {
    final out = Uint8List(IdGenerator.byteLength);
    var value = _value;
    for (var i = out.length - 1; i >= 0; i--) {
      out[i] = value & 0xFF;
      value >>= 8;
    }
    return out;
  }

  @override
  String generateId() => IdGenerator.bytesToString(generateBytes());
}
