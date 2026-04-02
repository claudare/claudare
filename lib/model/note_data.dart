class NoteData {
  final String noteId;

  final String title;
  final String content;

  final DateTime createdAt;
  final DateTime updatedAt;

  final bool isDeleted;

  const NoteData({
    required this.noteId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
  });

  NoteData copyWith({
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return NoteData(
      noteId: noteId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  toString() {
    return 'NoteData(noteId: $noteId, title: $title, content: $content, createdAt: $createdAt, updatedAt: $updatedAt, isDeleted: $isDeleted)';
  }
}
