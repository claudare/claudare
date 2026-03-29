import 'dart:typed_data';

import 'package:core/src/id_generator/id_generator.dart';

import 'random_source/random_source.dart';

import 'random_source/secure_random_source.dart';

// 16 bytes (128 bits) random ID generator.
// Uses secure source by default, but this should not be used for
// cryptographic operations. Use libsodium instead.
class RandomIdGenerator implements IdGenerator {
  final RandomSource randomSource;

  const RandomIdGenerator({RandomSource? randomSource})
    : randomSource = randomSource ?? const SecureRandomSource();

  @override
  Uint8List generateBytes() {
    final out = randomSource.nextBytes();
    assert(out.length == IdGenerator.byteLength);
    return out;
  }

  @override
  String generateId() {
    final s = IdGenerator.bytesToString(generateBytes());
    assert(s.length == IdGenerator.stringLength);
    return s;
  }
}
