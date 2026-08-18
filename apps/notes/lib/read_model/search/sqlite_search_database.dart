import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/read_model/search/search_projection_repo.dart';
import 'package:notes/read_model/search/search_read_model.dart';

class SqliteSearchDatabase implements SearchProjectionRepo, SearchReadModel {
  final IsolateSqlite _db;

  const SqliteSearchDatabase(this._db);

  void _optimizeSearchFts(SyncContext ctx) {
    ctx.execute("INSERT INTO fts(fts) VALUES('optimize');");
  }

  @override
  Future<void> reset() async {
    await _db.transaction((ctx) {
      ctx.execute('DROP TABLE IF EXISTS fts;');
      ctx.execute('DROP TABLE IF EXISTS meta;');
      ctx.execute('DROP TABLE IF EXISTS sequence;');
      ctx.execute('DROP TABLE IF EXISTS search;');
      ctx.execute('DROP TABLE IF EXISTS _migrations;');
      ctx.execute('''CREATE TABLE meta (
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
      ctx.execute('CREATE INDEX idx_meta_updated_at ON meta (updated_at);');
      ctx.execute('CREATE INDEX idx_meta_created_at ON meta (created_at);');
      ctx.execute('''CREATE VIRTUAL TABLE fts USING fts5(
        id UNINDEXED,
        title,
        content,
        tokenize = 'unicode61 remove_diacritics 2'
      )''');
      _optimizeSearchFts(ctx);
    });
  }

  @override
  Future<List<String>> query(String query) async {
    final ftsQuery = _toFtsQuery(query);
    if (ftsQuery == null) return const [];

    final rows = await _db.query(
      '''SELECT f.id
      FROM fts f
      JOIN meta m ON m.id = f.id
      WHERE fts MATCH ?
      ORDER BY
        bm25(fts, 10.0, 1.0),
        m.updated_at DESC,
        m.created_at DESC;''',
      [ftsQuery],
    );

    return rows.map((r) => r.field<String>('id')).toList(growable: false);
  }

  @override
  Future<void> upsertTitle(UpsertInput input) => _upsert(input, isTitle: true);

  @override
  Future<void> upsertContent(UpsertInput input) =>
      _upsert(input, isTitle: false);

  Future<void> _upsert(UpsertInput input, {required bool isTitle}) async {
    final timestamp = input.timestamp.millisecondsSinceEpoch;
    await _db.transaction((ctx) {
      final value =
          ctx.queryValue<String?>(
            isTitle
                ? 'SELECT content FROM fts WHERE id = ? LIMIT 1;'
                : 'SELECT title FROM fts WHERE id = ? LIMIT 1;',
            [input.noteId],
          ) ??
          '';
      final title = isTitle ? input.value : value;
      final content = isTitle ? value : input.value;

      ctx.execute('DELETE FROM fts WHERE id = ?;', [input.noteId]);
      ctx.execute('INSERT INTO fts (id, title, content) VALUES (?, ?, ?);', [
        input.noteId,
        title,
        content,
      ]);
      ctx.execute(
        '''INSERT INTO meta (id, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at;''',
        [input.noteId, timestamp, timestamp],
      );
    });
  }

  @override
  Future<void> permanentlyDelete(String noteId) async {
    await _db.transaction((tx) {
      tx.execute('DELETE FROM fts WHERE id = ?;', [noteId]);
      tx.execute('DELETE FROM meta WHERE id = ?;', [noteId]);
    });
  }
}

String? _toFtsQuery(String rawQuery) {
  final tokens = rawQuery
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .map((token) => '"${token.replaceAll('"', '""')}"*')
      .toList(growable: false);

  if (tokens.isEmpty) return null;
  return tokens.join(' AND ');
}
