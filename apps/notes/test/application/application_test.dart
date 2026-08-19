import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_application.dart';
import 'package:test/test.dart';

void main() {
  test('initializes', () async {
    final application = NoteApplication.test();
    addTearDown(() async {
      await application.close();
    });

    await application.initialize(
      notesDbFilepath: IsolateSqlite.memoryFilename,
      searchDbFilepath: IsolateSqlite.memoryFilename,
    );
  });
}
