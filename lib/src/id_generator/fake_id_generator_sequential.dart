import 'dart:typed_data';

import 'package:core/src/id_generator/id_generator.dart';

// [FakeIdGeneratorSequential] generates sequential ids starting at 0
class FakeIdGeneratorSequential implements IdGenerator {
  int sequence = 0;

  @override
  String generateId() {
    return "${sequence++}";
  }

  @override
  Uint8List generateBytes() {
    final out = Uint8List(IdGenerator.byteLength);
    var value = sequence++;
    for (var i = out.length - 1; i >= 0; i--) {
      out[i] = value & 0xFF;
      value >>= 8;
    }
    return out;
  }
}
