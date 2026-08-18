part of 'note.dart';

class NoteCreated extends NoteEvent {
  static const String kind = 'note.created'; // ill try with dots

  const NoteCreated();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  factory NoteCreated.fromJson(Map<String, dynamic> json) {
    return NoteCreated();
  }

  @override
  String toString() {
    return 'NoteCreated{}';
  }
}

final class NoteCreatedCodec implements EventCodec<NoteCreated> {
  const NoteCreatedCodec();

  @override
  String get kind => NoteCreated.kind;

  @override
  Uint8List toBytes(NoteCreated event) => JsonConverter.encode(event.toJson());

  @override
  NoteCreated fromBytes(Uint8List bytes) =>
      NoteCreated.fromJson(JsonConverter.decode(bytes));
}
