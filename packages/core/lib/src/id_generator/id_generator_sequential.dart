import 'dart:typed_data';

import 'package:core/src/id_generator/id_generator.dart';

class IdGeneratorSequential implements IdGenerator {
  int _value = 0;

  @override
  String generateId() => IdGenerator.bytesToString(generateBytes());

  @override
  Uint8List generateBytes() {
    final out = Uint8List(IdGenerator.byteLength);
    var value = _value++;
    for (var i = out.length - 1; i >= 0; i--) {
      out[i] = value & 0xFF;
      value >>= 8;
    }
    return out;
  }
}
