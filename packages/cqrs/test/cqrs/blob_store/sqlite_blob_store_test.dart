import 'dart:io';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite database;
  late SqliteBlobStore store;

  setUp(() async {
    database = IsolateSqlite();
    await database.openInMemory();
    store = SqliteBlobStore(database);
    await store.migrate();
  });
  tearDown(() => database.close());

  test('repeated migration preserves blob data', () async {
    await store.save('blob', Uint8List.fromList([0, 255]));
    await store.migrate();
    final other = SqliteBlobStore(database);
    await other.migrate();
    expect(await other.get('blob'), [0, 255]);
  });

  test('close closes the supplied database', () async {
    await store.close();
    await expectLater(database.query('SELECT 1;'), throwsStateError);
  });

  test('propagates database failures', () async {
    await database.execute('DROP TABLE blob_data;');
    await expectLater(store.get('blob'), throwsA(isA<SqliteException>()));
  });
}
