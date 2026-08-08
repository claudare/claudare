import 'package:core/src/cqrs/cqrs_runtime/runtime_repo/runtime_repo.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

class SqliteRuntimeRepo implements RuntimeRepo {
  final IsolateSqlite _db;

  const SqliteRuntimeRepo(this._db);

  @override
  Future<void> initialize() {
    return runtimeRepoMigrations.migrate(_db);
  }

  @override
  Future<int> getRuntimeVersion(String runtimeName) async {
    final value = await _db.queryValue<int?>(
      'SELECT version FROM runtime_repo_version WHERE runtime_name = ?',
      [runtimeName],
    );
    return value ?? 0;
  }

  @override
  Future<void> setRuntimeVersion(String runtimeName, int version) async {
    await _db.execute(
      'INSERT OR REPLACE INTO runtime_repo_version (runtime_name, version) VALUES (?, ?)',
      [runtimeName, version],
    );
  }
}

final runtimeRepoMigrations = SqliteMigrations(
  migrationTable: 'migrations_runtime_repo',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute(
      'CREATE TABLE runtime_repo_version (runtime_name TEXT PRIMARY KEY, version INTEGER)',
    );
  }),
);
