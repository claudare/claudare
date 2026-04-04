import 'package:core/crdt.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/repo/note/note_read_model.dart';

class SqliteNoteReadModel implements NoteReadModel {
  final IsolateSqlite _db;

  const SqliteNoteReadModel(this._db);

  @override
  Future<NoteData?> getNote(String noteId) async {
    final value = await _db.queryRow(
      'SELECT id, title, title_updated_at, content, created_at, updated_at, trashed_at FROM note WHERE id = ? LIMIT 1;',
      [noteId],
    );
    if (value == null) return null;

    return NoteData(
      noteId: value[0] as String,
      title: CrdtValueLatestWriteWins<String>(
        value[1] as String,
        DateTime.parse(value[2] as String),
      ),
      content: value[3] as String,
      createdAt: DateTime.parse(value[4] as String),
      updatedAt: DateTime.parse(value[5] as String),
      trashedAt: value[6] == null ? null : DateTime.parse(value[6] as String),
    );
  }

  @override
  Future<List<NoteData>> getAllNonDeletedNotes() async {
    final rows = await _db.query(
      'SELECT id, title, title_updated_at, content, created_at, updated_at, trashed_at FROM note WHERE trashed_at IS NULL;',
    );

    return rows
        .map(
          (row) => NoteData(
            noteId: row[0] as String,
            title: CrdtValueLatestWriteWins<String>(
              row[1] as String,
              DateTime.parse(row[2] as String),
            ),
            content: row[3] as String,
            createdAt: DateTime.parse(row[4] as String),
            updatedAt: DateTime.parse(row[5] as String),
            trashedAt: row[6] == null ? null : DateTime.parse(row[6] as String),
          ),
        )
        .toList();
  }
}
