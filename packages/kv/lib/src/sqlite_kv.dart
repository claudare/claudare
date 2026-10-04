import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:kv/src/kv.dart';

final _kvMigrations = SqliteMigrations(migrationTable: 'migrations_kv')
  ..add(
    SqliteMigration(1, (tx) {
      tx.execute('''CREATE TABLE kv_entry(
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    );''');
    }),
  );

/// Stores string values in an injected SQLite database.
class SqliteKv implements Kv {
  final IsolateSqlite _database;

  SqliteKv(IsolateSqlite database) : _database = database;

  /// Creates or migrates the KV schema before use.
  Future<void> migrate() => _kvMigrations.migrate(_database);

  /// Closes the supplied database after its consumers have stopped.
  Future<void> close() => _database.close();

  @override
  Future<String?> getString(String key) => _database.transaction((tx) {
    final row = tx.queryRow('SELECT value FROM kv_entry WHERE key = ?;', [key]);
    return row?.field<String>('value');
  });

  @override
  Future<void> setString(String key, String value) =>
      setAllStrings({key: value});

  @override
  Future<void> setAllStrings(Map<String, String> values) =>
      _database.transaction((tx) {
        for (final entry in values.entries) {
          tx.execute(
            '''INSERT INTO kv_entry(key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;''',
            [entry.key, entry.value],
          );
        }
      });

  @override
  Future<void> delete(String key) => _database.transaction((tx) {
    tx.execute('DELETE FROM kv_entry WHERE key = ?;', [key]);
  });

  @override
  Future<List<String>> listKeys(String prefix) => _database.transaction((tx) {
    final rows = tx.query(
      'SELECT key FROM kv_entry WHERE instr(key, ?) = 1 ORDER BY key;',
      [prefix],
    );
    return [for (final row in rows) row.field<String>('key')];
  });
}
