import 'package:core/src/database.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

void main() {
  group('database', () {
    test('create temporary', () async {
      final db = Database.temporary();

      final _migrations = SqliteMigrations(migrationTable: 'app_migrations')
        ..add(
          SqliteMigration(1, (tx) async {
            await tx.execute('''
            CREATE TABLE test (
              id VARCHAR(24) PRIMARY KEY NOT NULL
            );
          ''');
          }),
        );

      await _migrations.migrate(db.underlyingDb);

      await db.deinit();
    });
  });
}
