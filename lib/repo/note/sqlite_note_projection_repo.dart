import 'package:core/cqrs.dart';
import 'package:core/crdt.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/projection/note/note_projection_repo.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_migrations.dart';

class SqliteNoteProjectionRepo implements NoteProjectionRepo {
  final IsolateSqlite _db;

  const SqliteNoteProjectionRepo(this._db);

  @override
  Future<void> reset() async {
    await noteMigrations.migrate(_db);

    await _db.transaction((tx) {
      // reset only after the migrations were applied!
      tx.execute('DELETE FROM note;');
    });
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() async {
    // database could be not initialized at this point
    try {
      final localSequence = await _db.queryValue<int>(
        'SELECT COALESCE(MAX(_local_sequence), 0) FROM note;',
      );

      return ProjectionCheckpoint(localSequence);
    } catch (e) {
      print('failure of checkpoint in SqliteNoteInternalRepo: $e');
      return ProjectionCheckpoint.notInitialized();
    }
  }

  @override
  Future<void> store(NoteData note, int localSequence) async {
    await _db.execute(
      '''INSERT INTO note (
        id, title, title_updated_at, content, created_at, updated_at, trashed_at, _local_sequence
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?
      ) ON CONFLICT(id) DO UPDATE SET
        title=excluded.title,
        title_updated_at=excluded.title_updated_at,
        content=excluded.content,
        -- createdAt is never edited!
        updated_at=excluded.updated_at,
        trashed_at=excluded.trashed_at,
        _local_sequence=excluded._local_sequence;''',
      [
        note.noteId,
        note.title.value,
        note.title.occurredAt.toIso8601String(),
        note.content,
        note.createdAt.toIso8601String(),
        note.updatedAt.toIso8601String(),
        note.trashedAt?.toIso8601String(),
        localSequence,
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
    int localSequence,
    NoteData Function(NoteData) update,
  ) async {
    final data = await _get(noteId);
    if (data == null) {
      throw Exception('Note not found: $noteId');
    }
    await store(update(data), localSequence);
  }
}
