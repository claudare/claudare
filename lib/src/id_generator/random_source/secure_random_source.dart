import 'dart:math';
import 'dart:typed_data';

import '../id_generator.dart';
import 'random_source.dart';

/// Secure RNG used by the production ID generator.
class SecureRandomSource extends RandomSource {
  const SecureRandomSource();

  static final Random _secure = Random.secure();

  @override
  Uint8List nextBytes() {
    final b = Uint8List(IdGenerator.byteLength);
    for (var i = 0; i < b.length; i++) {
      b[i] = _secure.nextInt(256);
    }
    return b;
  }
}
