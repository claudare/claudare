import 'dart:collection';

import 'package:core/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/projection/search/search_projection_repo.dart';
import 'package:notes_app_v0/read_model/search/search_read_model.dart';

final _migrations = SqliteMigrations(migrationTable: '_migrations')..add(
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
);

class SqliteSearchRepo implements SearchProjectionRepo, SearchReadModel {
  final IsolateSqlite _db;

  const SqliteSearchRepo(this._db);

  @override
  Future<void> reset() async {
    await _migrations.migrate(_db);

    await _db.transaction((ctx) {
      ctx.execute('DELETE FROM search');
      ctx.execute('''INSERT INTO sequence (sequence) VALUES (0)
        ON CONFLICT(sequence) DO UPDATE SET sequence = 0''');
    });
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() async {
    final tableName = 'search';

    final tableCount = await _db.queryValue<int>('''
      SELECT count(*) FROM sqlite_master WHERE type='table' AND name='$tableName';
    ''');
    final isInitialized = tableCount == 1;

    if (!isInitialized) {
      return ProjectionCheckpoint.notInitialized();
    }

    final localSequence = await _db.queryValue<int?>(
      'SELECT sequence FROM sequence;',
    );
    if (localSequence == null) {
      return ProjectionCheckpoint.notInitialized();
    }

    // optimize fts on every startup
    // await _db.execute('''
    //     INSERT INTO $tableName($tableName) VALUES('optimize')
    //   ''');
    return ProjectionCheckpoint(localSequence);
  }

  @override
  Future<List<String>> query(String query) async {
    // titles are ranked before the content. Tags not implemented yet.
    // Sorted by change_order. Basically recent changes are shown first.

    final likeQuery = '%$query%';

    final (titleRows, contentRows) = await _db.transaction((ctx) {
      return (
        ctx.query(
          'SELECT id FROM search WHERE title LIKE ? ORDER BY change_order DESC;',
          [likeQuery],
        ),
        ctx.query(
          'SELECT id FROM search WHERE content LIKE ? ORDER BY change_order DESC;',
          [likeQuery],
        ),
      );
    });

    // default set that iterates in insertion order
    // https://api.flutter.dev/flutter/dart-core/Set-class.html
    // ignore: prefer_collection_literals
    final result = LinkedHashSet<String>();

    for (final row in titleRows) {
      result.add(row.field<String>('id'));
    }
    for (final row in contentRows) {
      result.add(row.field<String>('id'));
    }

    return result.toList();
  }

  @override
  Future<void> upsertTitle(
    String noteId,
    String value,
    int localSequence,
  ) async {
    await _db.transaction((ctx) {
      ctx.execute(
        '''
        INSERT INTO search (id, title, content, change_order)
        VALUES (?, ?, '', ?)
        ON CONFLICT(id) DO UPDATE SET title = excluded.title, change_order = excluded.change_order;
        ''',
        [noteId, value, localSequence],
      );
      ctx.execute('UPDATE sequence SET sequence = ?;', [localSequence]);
    });
  }

  @override
  Future<void> upsertContent(
    String noteId,
    String value,
    int localSequence,
  ) async {
    await _db.transaction((ctx) {
      ctx.execute(
        '''
        INSERT INTO search (id, title, content, change_order)
        VALUES (?, '', ?, ?)
        ON CONFLICT(id) DO UPDATE SET content = excluded.content, change_order = excluded.change_order;
        ''',
        [noteId, value, localSequence],
      );
      ctx.execute('UPDATE sequence SET sequence = ?;', [localSequence]);
    });
  }

  @override
  Future<void> permanentlyDelete(String noteId, int localSequence) async {
    await _db.transaction((tx) {
      tx.execute('DELETE FROM search WHERE id = ?;', [noteId]);
      tx.execute('UPDATE search SET _local_sequence = ?;', [localSequence]);
    });
  }
}
