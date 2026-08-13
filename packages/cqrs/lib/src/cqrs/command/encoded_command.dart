import 'dart:typed_data' show Uint8List;

class EncodedCommand {
  final String kind;
  final Uint8List bytes;

  const EncodedCommand({required this.kind, required this.bytes});
}
