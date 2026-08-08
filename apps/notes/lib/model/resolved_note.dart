/// [ResolvedNote] is a read-only representation of a note that has been fully resolved.
/// There is no CRDT information, only final values.
class ResolvedNote {
  final String noteId;

  final String title;
  final String content;

  final DateTime createdAt;
  final DateTime updatedAt;

  // nullable confustion here. untrashing will not be registered
  // hhhhh
  final DateTime? trashedAt;

  const ResolvedNote({
    required this.noteId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.trashedAt,
  });

  ResolvedNote.empty(this.noteId, DateTime currentTime)
    : title = '',
      content = '',
      createdAt = currentTime,
      updatedAt = currentTime,
      trashedAt = null;

  bool get isTrashed => trashedAt != null;

  ResolvedNote copyWith({
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ResolvedNote(
      noteId: noteId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trashedAt: trashedAt,
    );
  }

  // because null is both a value and default non-existing condition
  ResolvedNote copyTrashedSet({required DateTime trashedAt}) {
    return ResolvedNote(
      noteId: noteId,
      title: title,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      trashedAt: trashedAt,
    );
  }

  @override
  toString() {
    return 'NoteData(noteId: $noteId, title: $title, content: $content, createdAt: $createdAt, updatedAt: $updatedAt, trashedAt: $trashedAt)';
  }
}
