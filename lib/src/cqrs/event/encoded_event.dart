import 'dart:typed_data';

class EncodedEvent {
  final String kind;
  final Uint8List detail; // TODO: rename to "bytes"

  const EncodedEvent({required this.kind, required this.detail});
}
