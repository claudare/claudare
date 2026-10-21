import 'package:isolate_sqlite/isolate_sqlite.dart';

/// Resets database state and optionally reapplies migrations.
class SqliteReset {
  final String _migrationTable;
  final MigrationFn _resetFn;
  final SqliteMigrations? _migrations;

  const SqliteReset(this._migrationTable, this._resetFn, {this._migrations});

  /// Runs the reset transaction, then applies the configured migrations.
  Future<void> reset(IsolateSqlite db) async {
    await db.transaction((tx) {
      _resetFn(tx);
      tx.execute('DELETE FROM $_migrationTable;');
    });
    await _migrations?.migrate(db);
  }
}
