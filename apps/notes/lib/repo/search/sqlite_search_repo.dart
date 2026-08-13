import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/projection/search/search_projection_repo.dart';
import 'package:notes/read_model/search/search_read_model.dart';

final _migrations =
    SqliteMigrations(migrationTable: '_migrations')
      ..add(
        SqliteMigration(1, (ctx) {
          ctx.execute('''
      CREATE TABLE IF NOT EXISTS search (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        change_order INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS sequence (
        sequence INTEGER PRIMARY KEY
      );
    ''');
          ctx.execute('''
      CREATE INDEX idx_search_change_order ON search (change_order);
    ''');
        }),
      )
      ..add(
        SqliteMigration(2, (ctx) {
          ctx.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

          ctx.execute('''
      CREATE INDEX IF NOT EXISTS idx_meta_updated_at ON meta (updated_at);
    ''');
          ctx.execute('''
      CREATE INDEX IF NOT EXISTS idx_meta_created_at ON meta (created_at);
    ''');

          ctx.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(
        id UNINDEXED,
        title,
        content,
        tokenize = 'unicode61 remove_diacritics 2'
      );
    ''');

          // remove legacy tables
          // the database will be reset anyways after this upgrade
          ctx.execute('DROP INDEX IF EXISTS idx_search_change_order;');
          ctx.execute('DROP TABLE IF EXISTS search;');
        }),
      );

class SqliteSearchRepo implements SearchProjectionRepo, SearchReadModel {
  final IsolateSqlite _db;

  const SqliteSearchRepo(this._db);

  void _optimizeSeachFts(SyncContext ctx) {
    ctx.execute('''
        INSERT INTO fts(fts) VALUES('optimize');
      ''');
  }

  @override
  Future<void> reset() async {
    await _migrations.migrate(_db);

    await _db.transaction((ctx) {
      ctx.execute('DELETE FROM fts;');
      ctx.execute('DELETE FROM meta;');
      ctx.execute('DELETE FROM sequence;');
      ctx.execute('INSERT INTO sequence (sequence) VALUES (0);');
      _optimizeSeachFts(ctx);
    });
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() async {
    final sequenceExists = await _db.queryValue<int>('''
      SELECT count(*)
      FROM sqlite_master
      WHERE type = 'table' AND name = 'sequence';
    ''');

    if (sequenceExists != 1) {
      return ProjectionCheckpoint.notInitialized();
    }

    final localSequence = await _db.queryValue<int>(
      'SELECT sequence FROM sequence;',
    );
    // if (localSequence == null) {
    //   return ProjectionCheckpoint.notInitialized();
    // }

    await _db.run(_optimizeSeachFts);

    return ProjectionCheckpoint(localSequence);
  }

  @override
  Future<List<String>> query(String query) async {
    final ftsQuery = _toFtsQuery(query);
    if (ftsQuery == null) {
      return const [];
    }

    final rows = await _db.query(
      '''
      SELECT f.id
      FROM fts f
      JOIN meta m ON m.id = f.id
      WHERE fts MATCH ?
      ORDER BY
        bm25(fts, 10.0, 1.0),
        m.updated_at DESC,
        m.created_at DESC;
      ''',
      [ftsQuery],
    );

    return rows.map((r) => r.field<String>('id')).toList(growable: false);
  }

  @override
  Future<void> upsertTitle(UpsertInput input, int localSequence) async {
    final integerDatetime = input.timestamp.millisecondsSinceEpoch;

    await _db.transaction((ctx) {
      final prevContent =
          ctx.queryValue<String?>(
            '''
        SELECT content
        FROM fts
        WHERE id = ?
        LIMIT 1;
        ''',
            [input.noteId],
          ) ??
          '';

      ctx.execute('DELETE FROM fts WHERE id = ?;', [input.noteId]);
      ctx.execute(
        '''
        INSERT INTO fts (id, title, content)
        VALUES (?, ?, ?);
        ''',
        [input.noteId, input.value, prevContent],
      );

      ctx.execute(
        '''
        INSERT INTO meta (id, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at;
        ''',
        [input.noteId, integerDatetime, integerDatetime],
      );

      ctx.execute('UPDATE sequence SET sequence = ?;', [localSequence]);
    });
  }

  @override
  Future<void> upsertContent(UpsertInput input, int localSequence) async {
    final integerDatetime = input.timestamp.millisecondsSinceEpoch;

    await _db.transaction((ctx) {
      final prevTitle =
          ctx.queryValue<String?>(
            '''
        SELECT title
        FROM fts
        WHERE id = ?
        LIMIT 1;
        ''',
            [input.noteId],
          ) ??
          '';

      ctx.execute('DELETE FROM fts WHERE id = ?;', [input.noteId]);
      ctx.execute(
        '''
        INSERT INTO fts (id, title, content)
        VALUES (?, ?, ?);
        ''',
        [input.noteId, prevTitle, input.value],
      );

      ctx.execute(
        '''
        INSERT INTO meta (id, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at;
        ''',
        [input.noteId, integerDatetime, integerDatetime],
      );

      ctx.execute('UPDATE sequence SET sequence = ?;', [localSequence]);
    });
  }

  @override
  Future<void> permanentlyDelete(String noteId, int localSequence) async {
    await _db.transaction((tx) {
      tx.execute('DELETE FROM fts WHERE id = ?;', [noteId]);
      tx.execute('DELETE FROM meta WHERE id = ?;', [noteId]);
      tx.execute('UPDATE sequence SET sequence = ?;', [localSequence]);
    });
  }
}

String? _toFtsQuery(String rawQuery) {
  final tokens = rawQuery
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .map((t) => '"${t.replaceAll('"', '""')}"*')
      .toList(growable: false);

  if (tokens.isEmpty) {
    return null;
  }

  // Require all terms and allow prefix matching per term.
  return tokens.join(' AND ');
}
