import 'dart:typed_data';

import 'random_source.dart';

/// Deterministic source for (some?) tests.
/// Produces 16-byte big-endian counter values starting at 0.
class SequentialRandomSource extends RandomSource {
  int _counter = 0;

  SequentialRandomSource();

  @override
  Uint8List nextBytes() {
    final out = Uint8List(16);

    var v = _counter++;
    for (var i = 15; i >= 0; i--) {
      out[i] = v & 0xFF;
      v = v >> 8;
    }

    return out;
  }
}
