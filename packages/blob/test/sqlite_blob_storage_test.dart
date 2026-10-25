import 'package:blob/blob.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite database;
  late SqliteBlobStorage storage;

  setUp(() async {
    database = IsolateSqlite();
    await database.openInMemory();
    storage = SqliteBlobStorage(database);
    await storage.migrate();
  });
  tearDown(() => database.close());

  test('close closes the supplied database', () async {
    await storage.close();

    await expectLater(database.query('SELECT 1;'), throwsStateError);
  });

  test('propagates database failures', () async {
    await database.execute('DROP TABLE blob_storage;');

    await expectLater(storage.get('blob'), throwsA(isA<SqliteException>()));
  });
}
