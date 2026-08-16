part of 'note.dart';

class NoteTitleUpdated extends NoteEvent {
  static const String kind = 'note.title.updated';

  final String noteId; // TODO: this does not need to be here
  final String newTitle;

  const NoteTitleUpdated({required this.noteId, required this.newTitle});

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId, 'newTitle': newTitle};
  }

  factory NoteTitleUpdated.fromJson(Map<String, dynamic> json) {
    return NoteTitleUpdated(noteId: json['noteId'], newTitle: json['newTitle']);
  }

  @override
  String toString() {
    return 'NoteTitleUpdated{noteId: $noteId, newTitle: $newTitle}';
  }
}

final class NoteTitleUpdatedCodec implements EventCodec<NoteTitleUpdated> {
  const NoteTitleUpdatedCodec();

  @override
  String get kind => NoteTitleUpdated.kind;

  @override
  Uint8List toBytes(NoteTitleUpdated event) =>
      JsonConverter.encode(event.toJson());

  @override
  NoteTitleUpdated fromBytes(Uint8List bytes) =>
      NoteTitleUpdated.fromJson(JsonConverter.decode(bytes));
}
