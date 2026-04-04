import 'package:core/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/repo/note/note_internal_repo.dart';
import 'package:notes_app_v0/repo/note/note_migrations.dart';

// Get and store repo style
class SqliteNoteInternalRepo implements NoteInternalRepo {
  final IsolateSqlite _db;

  const SqliteNoteInternalRepo(this._db);

  @override
  Future<void> reset() async {
    // Should the reset drop and recreate schema as well?
    // This could be ran outside of the initialization.
    await _db.transaction((tx) {
      tx.exec('DROP TABLE IF EXISTS note;');
    });
    await noteMigrations.migrate(_db);
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() async {
    // database could be not initialized at this point
    try {
      final localSequence = await _db.queryValue<int>(
        'SELECT MAX(_local_sequence) FROM note;',
      );

      return ProjectionCheckpoint(localSequence: localSequence ?? 0);
    } catch (e) {
      // print('expected failure of checkpoint in SqliteNoteInternalRepo: $e');
      return ProjectionCheckpoint(localSequence: 0);
    }
  }

  @override
  Future<NoteData?> get(String noteId) async {
    final value = await _db.queryRow(
      'SELECT id, title, content, created_at, updated_at, is_deleted FROM note WHERE id = ? LIMIT 1;',
      [noteId],
    );
    if (value == null) return null;

    return NoteData(
      noteId: value[0] as String,
      title: value[1] as String,
      content: value[2] as String,
      createdAt: DateTime.parse(value[3] as String),
      updatedAt: DateTime.parse(value[4] as String),
      isDeleted: value[5] as int == 1,
    );
  }

  @override
  Future<void> store(NoteData note, int localSequence) async {
    await _db.exec(
      '''INSERT INTO note (
        id, title, content, created_at, updated_at, is_deleted, _local_sequence
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?
      ) ON CONFLICT(id) DO UPDATE SET
        title=excluded.title,
        content=excluded.content,
        updated_at=excluded.updated_at,
        is_deleted=excluded.is_deleted,
        _local_sequence=excluded._local_sequence;''',
      [
        note.noteId,
        note.title,
        note.content,
        note.createdAt.toIso8601String(),
        note.updatedAt.toIso8601String(),
        note.isDeleted ? 1 : 0,
        localSequence,
      ],
    );
  }

  @override
  Future<void> getAndStore(
    String noteId,
    int localSequence,
    NoteData Function(NoteData) update,
  ) async {
    final data = await get(noteId);
    if (data == null) {
      throw Exception('Note not found: $noteId');
    }
    await store(update(data), localSequence);
  }
}
