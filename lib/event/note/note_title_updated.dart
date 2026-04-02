part of 'note.dart';

class NoteTitleUpdated extends NoteEvent {
  static const String kind = 'note.title.updated';

  final String noteId;
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
