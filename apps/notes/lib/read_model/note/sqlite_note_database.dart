import 'package:crdt/crdt.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/read_model/note/note_data.dart';
import 'package:notes/read_model/note/note_projection_repo.dart';
import 'package:notes/read_model/note/resolved_note.dart';
import 'package:notes/read_model/note/resolved_note_read_model.dart';

class SqliteNoteDatabase implements NoteProjectionRepo, ResolvedNoteReadModel {
  final IsolateSqlite _db;

  const SqliteNoteDatabase(this._db);

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

  @override
  Future<List<ResolvedNote>> query(
    ResolvedNoteQueryCategory category,
    ResolvedNoteQueryOrder order,
  ) async {
    final rows = await _db.query(
      '''SELECT id, title, content, created_at, updated_at, trashed_at
      FROM note ${_categoryWhereSql(category)} ${_orderWhereSql(order)};''',
    );

    return rows.map(_resolvedNoteFromRow).toList();
  }

  @override
  Future<ResolvedNote?> getById(String noteId) async {
    final row = await _db.queryRow(
      'SELECT id, title, content, created_at, updated_at, trashed_at FROM note WHERE id = ? LIMIT 1;',
      [noteId],
    );
    return row == null ? null : _resolvedNoteFromRow(row);
  }

  @override
  Future<List<ResolvedNote>> getManyById(List<String> noteIds) async {
    if (noteIds.isEmpty) return [];

    final rows = await _db.query(
      '''SELECT id, title, content, created_at, updated_at, trashed_at
      FROM note
      WHERE id IN (${noteIds.map((_) => '?').join(', ')});''',
      noteIds,
    );

    return rows.map(_resolvedNoteFromRow).toList();
  }

  ResolvedNote _resolvedNoteFromRow(Row row) {
    final trashedAt = row.field<String?>('trashed_at');
    return ResolvedNote(
      noteId: row.field('id'),
      title: row.field('title'),
      content: row.field('content'),
      createdAt: DateTime.parse(row.field<String>('created_at')),
      updatedAt: DateTime.parse(row.field<String>('updated_at')),
      trashedAt: trashedAt == null ? null : DateTime.parse(trashedAt),
    );
  }

  String _orderWhereSql(ResolvedNoteQueryOrder order) {
    switch (order) {
      case ResolvedNoteQueryOrder.createdAtDescending:
        return 'ORDER BY created_at DESC';
      case ResolvedNoteQueryOrder.createdAtAscending:
        return 'ORDER BY created_at ASC';
      case ResolvedNoteQueryOrder.updatedAtDescending:
        return 'ORDER BY updated_at DESC';
      case ResolvedNoteQueryOrder.updatedAtAscending:
        return 'ORDER BY updated_at ASC';
    }
  }

  String _categoryWhereSql(ResolvedNoteQueryCategory category) {
    switch (category) {
      case ResolvedNoteQueryCategory.all:
        return '';
      case ResolvedNoteQueryCategory.notTrashed:
        return 'WHERE trashed_at IS NULL';
      case ResolvedNoteQueryCategory.trashed:
        return 'WHERE trashed_at IS NOT NULL';
      case ResolvedNoteQueryCategory.favorited:
        return 'WHERE 1 = 2';
    }
  }
}
