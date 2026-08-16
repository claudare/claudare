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

  @override
  Future<RuntimeProjectionBoundaries?> getProjectionBoundaries(
    String name,
  ) async {
    final row = await _database.queryRow(
      'SELECT applying_sequence, applied_sequence FROM runtime_projection WHERE name = ?',
      [name],
    );
    if (row == null) return null;
    return RuntimeProjectionBoundaries(
      applyingSequence: row[0] as int?,
      appliedSequence: row[1] as int?,
    );
  }

  @override
  Future<void> setProjectionBoundaries(
    String name, {
    required int? applyingSequence,
    required int? appliedSequence,
  }) => _database.execute(
    '''INSERT INTO runtime_projection (name, applying_sequence, applied_sequence)
       VALUES (?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET
         applying_sequence = excluded.applying_sequence,
         applied_sequence = excluded.applied_sequence''',
    [name, applyingSequence, appliedSequence],
  );
}

final runtimeDatabaseMigrations =
    SqliteMigrations(migrationTable: 'migrations_runtime_database')
      ..add(
        SqliteMigration(1, (tx) {
          tx.execute(
            'CREATE TABLE runtime_database_version (runtime_name TEXT PRIMARY KEY, version INTEGER)',
          );
        }),
      )
      ..add(
        SqliteMigration(2, (tx) {
          tx.execute('''CREATE TABLE runtime_projection (
      name TEXT PRIMARY KEY,
      applying_sequence INTEGER,
      applied_sequence INTEGER
    )''');
        }),
      );
