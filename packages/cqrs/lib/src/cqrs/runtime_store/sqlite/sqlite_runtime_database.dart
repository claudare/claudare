import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

class SqliteRuntimeDatabase implements RuntimeDatabase {
  final IsolateSqlite _database;

  const SqliteRuntimeDatabase(this._database);

  @override
  Future<void> initialize() => runtimeDatabaseMigrations.migrate(_database);

  @override
  Future<RuntimeProjectionState?> getProjectionState(String name) async {
    final row = await _database.queryRow(
      '''SELECT version, applying_through_local_sequence,
                scanned_through_local_sequence
         FROM runtime_projection WHERE name = ?''',
      [name],
    );
    if (row == null) return null;
    return RuntimeProjectionState(
      version: row[0] as int,
      applyingThroughLocalSequence: row[1] as int?,
      scannedThroughLocalSequence: row[2] as int?,
    );
  }

  @override
  Future<void> setProjectionState(String name, RuntimeProjectionState state) =>
      _database.execute(
        '''INSERT INTO runtime_projection (
         name, version, applying_through_local_sequence,
         scanned_through_local_sequence
       ) VALUES (?, ?, ?, ?)
       ON CONFLICT(name) DO UPDATE SET
         version = excluded.version,
         applying_through_local_sequence =
           excluded.applying_through_local_sequence,
         scanned_through_local_sequence =
           excluded.scanned_through_local_sequence''',
        [
          name,
          state.version,
          state.applyingThroughLocalSequence,
          state.scannedThroughLocalSequence,
        ],
      );
}

final runtimeDatabaseMigrations = SqliteMigrations(
  migrationTable: 'migrations_runtime_database',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute('''CREATE TABLE runtime_projection (
      name TEXT PRIMARY KEY,
      version INTEGER NOT NULL,
      applying_through_local_sequence INTEGER,
      scanned_through_local_sequence INTEGER
    )''');
  }),
);
