import 'dart:math';
import 'dart:typed_data';

import '../id_generator.dart';
import 'random_source.dart';

/// Seeded RNG (deterministic, for tests).
class SeededRandomSource extends RandomSource {
  final Random _random;

  SeededRandomSource(int seed) : _random = Random(seed);

  @override
  Uint8List nextBytes() {
    final b = Uint8List(IdGenerator.byteLength);
    for (var i = 0; i < b.length; i++) {
      b[i] = _random.nextInt(256);
    }
    return b;
  }
}
