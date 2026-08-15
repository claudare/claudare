import 'dart:typed_data';

class EncodedEvent {
  final String kind;
  final Uint8List bytes;

  EncodedEvent({required this.kind, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
}
