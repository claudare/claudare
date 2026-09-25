part of 'note.dart';

class NoteTrashed extends NoteEvent {
  static const String kind = 'note.trashed';

  @override
  final String noteId;

  const NoteTrashed({required this.noteId});

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId};
  }

  factory NoteTrashed.fromJson(Map<String, dynamic> json) {
    return NoteTrashed(noteId: json['noteId'] as String);
  }

  @override
  String toString() {
    return 'NoteTrashed{}';
  }
}

final class NoteTrashedCodec implements EventCodec<NoteTrashed> {
  const NoteTrashedCodec();

  @override
  String get kind => NoteTrashed.kind;

  @override
  Uint8List toBytes(NoteTrashed event) => JsonConverter.encode(event.toJson());

  @override
  NoteTrashed fromBytes(Uint8List bytes) =>
      NoteTrashed.fromJson(JsonConverter.decode(bytes));
}
