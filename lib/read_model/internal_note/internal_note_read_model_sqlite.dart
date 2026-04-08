import 'package:core/crdt.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/read_model/internal_note/internal_note_read_model.dart';

class InternalNoteReadModelSqlite implements InternalNoteReadModel {
  final IsolateSqlite _db;

  const InternalNoteReadModelSqlite(this._db);

  @override
  Future<NoteData> getNote(String noteId) async {
    final value = await _db.queryRow(
      'SELECT id, title, title_updated_at, content, created_at, updated_at, trashed_at FROM note WHERE id = ? LIMIT 1;',
      [noteId],
    );
    if (value == null) {
      throw StateError('Note not found');
    }

    return NoteData(
      noteId: value[0] as String,
      title: CrdtValueLatestWriteWins(
        value[1] as String,
        DateTime.parse(value[2] as String),
      ),
      content: value[3] as String,
      createdAt: DateTime.parse(value[4] as String),
      updatedAt: DateTime.parse(value[5] as String),
      trashedAt: value[6] == null ? null : DateTime.parse(value[6] as String),
    );
  }
}
