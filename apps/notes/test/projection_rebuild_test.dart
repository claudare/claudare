import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/event/note.dart';
import 'package:notes/projection/note_projection.dart';
import 'package:notes/projection/search_projection.dart';
import 'package:notes/read_model/note/sqlite_note_database.dart';
import 'package:notes/read_model/search/sqlite_search_database.dart';
import 'package:test/test.dart';

void main() {
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);

  test('note projection rebuilds', () async {
    final database = IsolateSqlite();
    await database.openInMemory();
    addTearDown(database.close);

    final noteDatabase = SqliteNoteDatabase(database);
    final projection = NoteProjection(noteDatabase);
    final tester =
        ProjectionTester(projection)
          ..withEvent('note/note-1', const NoteCreated(), occuredAt: occurredAt)
          ..withEvent(
            'note/note-1',
            const NoteTitleUpdated(noteId: 'note-1', newTitle: 'Title'),
            occuredAt: occurredAt,
          );
    final readModel = noteDatabase;

    expect(await tester.run(), isTrue);
    final first = await readModel.getById('note-1');
    expect(first?.title, 'Title');

    expect(await tester.run(), isTrue);
    final rebuilt = await readModel.getById('note-1');
    expect(rebuilt?.toString(), first?.toString());
  });

  test('search projection rebuilds', () async {
    final database = IsolateSqlite();
    await database.openInMemory();
    addTearDown(database.close);

    final repository = SqliteSearchDatabase(database);
    final projection = SearchProjection(repository, const NoopLogger());
    final tester = ProjectionTester(projection)..withEvent(
      'note/note-1',
      const NoteTitleUpdated(noteId: 'note-1', newTitle: 'hello'),
      occuredAt: occurredAt,
    );

    expect(await tester.run(), isTrue);
    expect(await repository.query('hello'), ['note-1']);
    expect(await tester.run(), isTrue);
    expect(await repository.query('hello'), ['note-1']);
  });
}
