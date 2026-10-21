import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite db;
  late SqliteMigrations migrations;

  setUp(() async {
    db = IsolateSqlite();
    await db.openInMemory();
    addTearDown(db.close);
    migrations = _createMigrations();
    await migrations.migrate(db);
  });

  group('SqliteReset', () {
    for (final emptyHistory in [false, true]) {
      test('clears ${emptyHistory ? 'empty' : 'populated'} migration history '
          'and retains its table', () async {
        if (emptyHistory) {
          await db.execute('DELETE FROM test_migrations');
        }
        final reset = SqliteReset('test_migrations', (tx) {});

        await reset.reset(db);

        expect(
          await db.queryValue<int>('SELECT COUNT(*) FROM test_migrations'),
          0,
        );
      });
    }

    test('can round-trip migrate-reset-migrate', () async {
      final reset = SqliteReset('test_migrations', (tx) {
        tx.execute('DROP TABLE records');
      });

      await _expectMigrated(db);

      await reset.reset(db);
      await _expectReset(db);

      await migrations.migrate(db);
      await _expectMigrated(db);
    });

    test('can reset after a reset', () async {
      final reset = SqliteReset('test_migrations', (tx) {
        tx.execute('DROP TABLE IF EXISTS records');
      });

      await reset.reset(db);
      await _expectReset(db);

      await reset.reset(db);
      await _expectReset(db);
    });

    test('runs the callback before clearing migration history', () async {
      final reset = SqliteReset('test_migrations', (tx) {
        tx.execute('''
          UPDATE records SET id = (SELECT COUNT(*) FROM test_migrations)
        ''');
      });

      await reset.reset(db);

      expect(await db.queryValue<int>('SELECT id FROM records'), 2);
    });
}

SqliteMigrations _createMigrations() {
  return SqliteMigrations(migrationTable: 'test_migrations')
    ..add(
      SqliteMigration(1, (tx) {
        tx.execute('CREATE TABLE records (id INTEGER PRIMARY KEY)');
      }),
    )
    ..add(
      SqliteMigration(2, (tx) {
        tx.execute('INSERT INTO records (id) VALUES (1)');
      }),
    );
}

Future<void> _expectMigrated(IsolateSqlite db) async {
  expect(await db.queryValue<int>('SELECT id FROM records'), 1);
  final history = await db.query(
    'SELECT version FROM test_migrations ORDER BY version',
  );
  expect(history.map((row) => row[0]), [1, 2]);
}

Future<void> _expectReset(IsolateSqlite db) async {
  expect(
    await db.queryValue<int>(
      "SELECT COUNT(*) FROM sqlite_schema WHERE name = 'records'",
    ),
    0,
  );
  expect(await db.queryValue<int>('SELECT COUNT(*) FROM test_migrations'), 0);
}

void _throwResetException(SyncContext tx) {
  throw Exception('reset failed');
}

void _executeInvalidSql(SyncContext tx) {
  tx.execute('INVALID RESET SQL');
}
