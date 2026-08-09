import 'dart:math';
import 'dart:typed_data';

import 'package:id_generator/src/id_generator.dart';

class IdGeneratorSeeded implements IdGenerator {
  final Random _random;

  IdGeneratorSeeded(int seed) : _random = Random(seed);

  @override
  Uint8List generateBytes() {
    final bytes = Uint8List(IdGenerator.byteLength);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  @override
  String generateId() => IdGenerator.bytesToString(generateBytes());
}
