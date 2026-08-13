import 'dart:typed_data';

abstract interface class CommandInput {
  String get kind;

  Uint8List encode();
}
