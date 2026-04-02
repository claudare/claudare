import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/repo/note/note_read_model.dart';

class SqliteNoteReadModel implements NoteReadModel {
  final IsolateSqlite _db;

  const SqliteNoteReadModel(this._db);

  @override
  Future<List<NoteData>> getAllNotes() async {
    final rows = await _db.query(
      'SELECT id, title, content, created_at, updated_at FROM note WHERE is_deleted = 0;',
    );
    return rows
        .map(
          (row) => NoteData(
            noteId: row[0] as String,
            title: row[1] as String,
            content: row[2] as String,
            createdAt: DateTime.parse(row[3] as String),
            updatedAt: DateTime.parse(row[4] as String),
            isDeleted: false,
          ),
        )
        .toList();
  }

  @override
  Future<List<NoteData>> getAllDeletedNotes() async {
    final rows = await _db.query(
      'SELECT id, title, content, created_at, updated_at FROM note WHERE is_deleted = 1;',
    );
    return rows
        .map(
          (row) => NoteData(
            noteId: row[0] as String,
            title: row[1] as String,
            content: row[2] as String,
            createdAt: DateTime.parse(row[3] as String),
            updatedAt: DateTime.parse(row[4] as String),
            isDeleted: true,
          ),
        )
        .toList();
  }
}
