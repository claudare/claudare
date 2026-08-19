import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/fake_application_factory.dart';
import 'package:test/test.dart';

void main() {
  test('initializes', () async {
    final application = FakeApplicationFactory().create();
    addTearDown(() async {
      await application.searchDb.close();
      await application.sqliteDb.close();
    });

    await application.initialize(
      notesDbFilepath: IsolateSqlite.memoryFilename,
      searchDbFilepath: IsolateSqlite.memoryFilename,
    );
  });
}
