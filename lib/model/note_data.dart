import 'package:core/crdt.dart';

/// [NoteData] is the full internal, CRDT-centric data representation
class NoteData {
  final String noteId;

  final CrdtValueLatestWriteWins<String> title;
  final String content;

  final DateTime createdAt;
  final DateTime updatedAt;

  // nullable confustion here. untrashing will not be registered
  // hhhhh
  final DateTime? trashedAt;

  const NoteData({
    required this.noteId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.trashedAt,
  });

  NoteData.empty(this.noteId, DateTime currentTime)
    : title = CrdtValueLatestWriteWins<String>.zero(''),
      content = '',
      createdAt = currentTime,
      updatedAt = currentTime,
      trashedAt = null;

  bool get isTrashed => trashedAt != null;

  NoteData copyWith({
    CrdtValueDateTimePair<String>? titlePair,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final newTitle = titlePair == null ? title : title.mergePair(titlePair);

    return NoteData(
      noteId: noteId,
      title: newTitle,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trashedAt: trashedAt,
    );
  }

  // because null is both a value and default non-existing condition
  NoteData copyWithTrashedValue({required DateTime? trashedAt}) {
    return NoteData(
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
    return 'NoteData(noteId: $noteId, title: ${title.value}, content: $content, createdAt: $createdAt, updatedAt: $updatedAt, trashedAt: $trashedAt)';
  }
}
