import 'package:crdt/crdt.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/model/note_data.dart';
import 'package:notes/projection/note/note_projection_repo.dart';

class SqliteNoteProjectionRepo implements NoteProjectionRepo {
  final IsolateSqlite _db;
  const SqliteNoteProjectionRepo(this._db);

  @override
  Future<void> reset() async {
    await _db.transaction((tx) {
      tx.execute('DROP TABLE IF EXISTS note;');
      tx.execute('''CREATE TABLE note (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        title_updated_at TEXT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        trashed_at TEXT
      )''');
      tx.execute(
        'CREATE INDEX idx_note_id_trashed_at ON note(id, trashed_at);',
      );
    });
  }

  @override
  Future<void> store(NoteData note) async {
    await _db.execute(
      '''INSERT INTO note (
        id, title, title_updated_at, content, created_at, updated_at, trashed_at
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?
      ) ON CONFLICT(id) DO UPDATE SET
        title=excluded.title,
        title_updated_at=excluded.title_updated_at,
        content=excluded.content,
        -- createdAt is never edited!
        updated_at=excluded.updated_at,
        trashed_at=excluded.trashed_at;''',
      [
        note.noteId,
        note.title.value,
        note.title.occurredAt.toIso8601String(),
        note.content,
        note.createdAt.toIso8601String(),
        note.updatedAt.toIso8601String(),
        note.trashedAt?.toIso8601String(),
      ],
    );
  }

  Future<NoteData?> _get(String noteId) async {
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
  Future<void> getAndStore(
    String noteId,
    NoteData Function(NoteData) update,
  ) async {
    final data = await _get(noteId);
    if (data == null) {
      throw Exception('Note not found: $noteId');
    }
    await store(update(data));
  }
}
