import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

class SqliteRuntimeDatabase implements RuntimeDatabase {
  final IsolateSqlite _database;

  const SqliteRuntimeDatabase(this._database);

  @override
  Future<void> initialize() => runtimeDatabaseMigrations.migrate(_database);

  @override
  Future<int> getRuntimeVersion(String runtimeName) async {
    final value = await _database.queryValue<int?>(
      'SELECT version FROM runtime_database_version WHERE runtime_name = ?',
      [runtimeName],
    );
    return value ?? 0;
  }

  @override
  Future<void> setRuntimeVersion(
    String runtimeName,
    int version,
  ) => _database.execute(
    'INSERT OR REPLACE INTO runtime_database_version (runtime_name, version) VALUES (?, ?)',
    [runtimeName, version],
  );
}

final runtimeDatabaseMigrations = SqliteMigrations(
  migrationTable: 'migrations_runtime_database',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute(
      'CREATE TABLE runtime_database_version (runtime_name TEXT PRIMARY KEY, version INTEGER)',
    );
  }),
);
