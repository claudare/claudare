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
    // TODO: implement generateBytes
    throw UnimplementedError();
  }
}
