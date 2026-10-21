import 'package:isolate_sqlite/isolate_sqlite.dart';

class SqliteReset {
  final String _migrationTable;
  final MigrationFn _resetFn;

  const SqliteReset(this._migrationTable, this._resetFn);

  Future<void> reset(IsolateSqlite db) async {
    await db.transaction((tx) {
      _resetFn(tx);
      tx.execute('DELETE FROM $_migrationTable;');
    });
  }
}
