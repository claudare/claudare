import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes_app/notes_app.dart';
import 'package:test/test.dart';

void main() {
  test(
    'tracked note catchup retains documents across paginated reads',
    () async {
      final store = MemoryEventStore(eventFetchPageSize: 1);
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
      final id = app.generateNoteId();
      await app.command.createNote(id);
      final note = app.query.trackNote(id);
      await app.query.catchupNote(note);
      final document = note.contentDocument;

      final other = app.generateNoteId();
      await app.command.createNote(other);
      await app.command.updateNoteTitle(other, 'Other');
      await app.command.updateNoteTitle(id, 'Title');
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        'Body',
        actorId: 'remote',
      );

      await app.query.catchupNote(note);
      expect(note.title, 'Title');
      expect(note.content, 'Body');
      expect(note.contentDocument, same(document));
      await app.query.catchupNote(note);
      expect(note.content, 'Body');
    },
  );

  test('catchup rejects note states that were not tracked', () async {
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
    final state = await app.query.note('missing');

    await expectLater(app.query.catchupNote(state), throwsArgumentError);
  });
}
