import 'package:test/test.dart';

import 'package:isolate_sqlite/isolate_sqlite.dart';

void main() {
  late IsolateSqlite db;

  setUp(() async {
    db = IsolateSqlite();
    await db.openInMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('applies pending migrations once, in order', () async {
    final migrations = SqliteMigrations(migrationTable: 'test_migrations')
      ..add(
        SqliteMigration(0, (tx) {
          tx.execute('CREATE TABLE t1 (id TEXT PRIMARY KEY, name STRING)');
          tx.execute('CREATE INDEX idx_name ON t1(name);');
        }),
      )
      ..add(
        SqliteMigration(1, (tx) {
          tx.execute('ALTER TABLE t1 ADD COLUMN eye_color TEXT');
        }),
      )
      ..add(
        SqliteMigration(2, (tx) {
          tx.execute('CREATE TABLE t2 (id INTEGER PRIMARY KEY)');
        }),
      );

    // first run
    await migrations.migrate(db);

    // tables exist
    final tables = await db.query(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((r) => r[0] as String).toList();
    expect(names, containsAll(['t1', 't2', 'test_migrations']));

    // migration rows
    final applied = await db.query(
      'SELECT version FROM test_migrations ORDER BY version',
    );
    expect(applied.map((r) => r[0]), [0, 1, 2]);

    // second run should do nothing
    await migrations.migrate(db);

    final applied2 = await db.query(
      'SELECT version FROM test_migrations ORDER BY version',
    );
    expect(applied2.length, 3);
  });

  test('can modify tables and insert data', () async {
    final migrations = SqliteMigrations(migrationTable: 'test_migrations')
      ..add(
        SqliteMigration(0, (tx) async {
          tx.execute('CREATE TABLE t1 (id TEXT PRIMARY KEY, name STRING)');
          tx.execute('CREATE INDEX idx_name ON t1(name);');
          tx.execute('INSERT INTO t1 (id, name) VALUES (?, ?)', ['1', 'Alice']);
          tx.execute('INSERT INTO t1 (id, name) VALUES (?, ?)', ['2', 'Bob']);
        }),
      );

    // first run
    await migrations.migrate(db);

    // tables were created exist
    final tables = await db.query(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((r) => r[0] as String).toList();
    expect(names, containsAll(['t1', 'test_migrations']));

    // verify data was added
    final result = await db.query('SELECT * FROM t1');
    expect(result.data, [
      ['1', 'Alice'],
      ['2', 'Bob'],
    ]);
  });

  for (final versions in [
    [1],
    [-1],
    [0, 0],
    [0, 2],
    [0, 1, 0],
  ]) {
    test('rejects migration declaration order $versions', () {
      final migrations = SqliteMigrations(migrationTable: 'test_migrations');

      expect(() {
        for (final version in versions) {
          migrations.add(SqliteMigration(version, (tx) {}));
        }
      }, throwsArgumentError);
    });
  }

  for (final counts in [(applied: 4, defined: 1), (applied: 1, defined: 0)]) {
    test('rejects ${counts.applied} applied migrations when '
        '${counts.defined} are defined', () async {
      await _createMigrations(counts.applied).migrate(db);

      await expectLater(
        _createMigrations(counts.defined).migrate(db),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('is not defined'),
          ),
        ),
      );

      final applied = await db.query(
        'SELECT version FROM test_migrations ORDER BY version',
      );
      expect(
        applied.map((row) => row[0]),
        List.generate(counts.applied, (i) => i),
      );
    });
  }

  test('applies a migration appended after an earlier run', () async {
    final migrations = _createMigrations(1);
    await migrations.migrate(db);
    migrations.add(SqliteMigration(1, (tx) {}));

    await migrations.migrate(db);

    final applied = await db.query(
      'SELECT version FROM test_migrations ORDER BY version',
    );
    expect(applied.map((row) => row[0]), [0, 1]);
  });

  test(
    'rolls back pending changes and their migration records on failure',
    () async {
      final migrations = SqliteMigrations(migrationTable: 'test_migrations')
        ..add(
          SqliteMigration(0, (tx) {
            tx.execute('CREATE TABLE records (id INTEGER PRIMARY KEY)');
          }),
        );
      await migrations.migrate(db);
      migrations
        ..add(
          SqliteMigration(1, (tx) {
            tx.execute('INSERT INTO records (id) VALUES (1)');
          }),
        )
        ..add(
          SqliteMigration(2, (tx) {
            throw StateError('Migration failed');
          }),
        );

      await expectLater(migrations.migrate(db), throwsStateError);

      expect(await db.queryValue<int>('SELECT COUNT(*) FROM records'), 0);
      final applied = await db.query(
        'SELECT version FROM test_migrations ORDER BY version',
      );
      expect(applied.map((row) => row[0]), [0]);
    },
  );
}

SqliteMigrations _createMigrations(int count) {
  final migrations = SqliteMigrations(migrationTable: 'test_migrations');
  for (var version = 0; version < count; version++) {
    migrations.add(SqliteMigration(version, (tx) {}));
  }
  return migrations;
}
