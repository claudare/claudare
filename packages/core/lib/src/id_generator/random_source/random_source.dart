import 'dart:typed_data';

abstract class RandomSource {
  const RandomSource();

  Uint8List nextBytes();
}
