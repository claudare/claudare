import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:test/test.dart';

void main() {
  test('live note catchup retains documents across paginated reads', () async {
    final store = MemoryEventStore(eventFetchPageSize: 1);
    final app = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      fts: NoopFts(),
      logger: const NoopLogger(),
    );
    final id = app.generateNoteId();
    await app.command.createNote(id);
    final live = app.query.liveNote(id);
    addTearDown(live.stop);
    final note = await live.latest();
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

    await live.latest();
    expect(note.title, 'Title');
    expect(note.content, 'Body');
    expect(note.contentDocument, same(document));
    await live.latest();
    expect(note.content, 'Body');
  });
}
