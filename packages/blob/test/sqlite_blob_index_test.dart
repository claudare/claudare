import 'package:blob/blob.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite database;
  late SqliteBlobIndex index;

  setUp(() async {
    database = IsolateSqlite();
    await database.openInMemory();
    index = SqliteBlobIndex(database);
    await index.migrate();
  });
  tearDown(() => database.close());

  test('close closes the supplied database', () async {
    await index.close();

    await expectLater(database.query('SELECT 1;'), throwsStateError);
  });

  test('propagates database failures', () async {
    await database.execute('DROP TABLE blob_index;');

    await expectLater(index.get('blob'), throwsA(isA<SqliteException>()));
  });
}
