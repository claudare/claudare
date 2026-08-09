import 'dart:math';
import 'dart:typed_data';

import 'package:core/src/id_generator/id_generator.dart';

class IdGeneratorSecure implements IdGenerator {
  final Random _random = Random.secure();

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
