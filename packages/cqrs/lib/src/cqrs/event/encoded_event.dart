import 'dart:typed_data';

class EncodedEvent {
  final String kind;
  final Uint8List bytes;

  const EncodedEvent({required this.kind, required this.bytes});
}
