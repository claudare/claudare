import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  test('memory filename opens a usable database', () async {
    final database = IsolateSqlite();
    addTearDown(database.close);

    await database.open(IsolateSqlite.memoryFilename);
    await database.execute('CREATE TABLE example (value TEXT NOT NULL)');
    await database.execute('INSERT INTO example (value) VALUES (?)', [
      'stored',
    ]);

    expect(
      await database.queryValue<String>('SELECT value FROM example'),
      'stored',
    );
  });
}
