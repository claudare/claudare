part of 'note.dart';

class NoteCreated extends NoteEvent {
  static const String kind = 'note.created'; // ill try with dots

  @override
  final String noteId;

  const NoteCreated({required this.noteId});

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId};
  }

  factory NoteCreated.fromJson(Map<String, dynamic> json) {
    return NoteCreated(noteId: json['noteId'] as String);
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
