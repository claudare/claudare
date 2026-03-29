import 'dart:typed_data';

import 'id_generator.dart';
import 'package:uuid/uuid.dart';

class UuidIdGenerator implements IdGenerator {
  final _uuid = Uuid();

  UuidIdGenerator();

  @override
  String generateId() {
    final obj = _uuid.v4obj();

    // this should default to strong rng
    return _uuid.v4();
  }

  Uint8List asBytes(String s) {
    final bytes = Uint8List.fromList(Uuid.parse(s));

    assert(bytes.length == 16, 'UUID bytes must be 16 bytes');
    return bytes;
  }
}
