import 'package:core/src/database.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

class _TestDb extends DatabaseBase {
  _TestDb.temporary() : super.temporary();
}

void main() {
  group('DatabaseBase', () {
    test('create temporary', () async {
      final db = _TestDb.temporary();

      final migrations = SqliteMigrations(migrationTable: 'app_migrations')
        ..add(
          SqliteMigration(1, (tx) async {
            await tx.execute('''
            CREATE TABLE test (
              id VARCHAR(24) PRIMARY KEY NOT NULL
            );
          ''');
          }),
        );

      await migrations.migrate(db.db);

      await db.deinit();
      await databaseDELETE(db);
    });
  });
}
