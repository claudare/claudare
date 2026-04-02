part of 'note.dart';

class NoteContentUpdated extends NoteEvent {
  static const String kind = 'note.content.updated';

  final String noteId;
  final String newContent;

  const NoteContentUpdated({required this.noteId, required this.newContent});

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId, 'newContent': newContent};
  }

  factory NoteContentUpdated.fromJson(Map<String, dynamic> json) {
    return NoteContentUpdated(
      noteId: json['noteId'],
      newContent: json['newContent'],
    );
  }

  @override
  String toString() {
    return 'NoteContentUpdated{noteId: $noteId, newContent: $newContent}';
  }
}
