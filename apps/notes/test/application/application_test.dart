import 'package:cqrs/cqrs_test_utils.dart';
import 'package:crdt/crdt_text.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/event/note.dart';
import 'package:test/test.dart';

void main() {
  late CqrsTestRuntime runtime;
  late NoteApplication application;

  setUp(() {
    runtime = CqrsTestRuntime();
    application = NoteApplication(cqrsRuntime: runtime);
  });

  test('returns absent state for a note that was never created', () async {
    expect((await application.query.note('missing')).exists, isFalse);
    expect(await application.query.noteList(), isEmpty);
  });

  test('create generates a usable note ID', () async {
    final noteId = await application.command.createNote();

    expect(noteId, hasLength(IdGenerator.stringLength));
    final note = await application.query.note(noteId);
    expect(note.exists, isTrue);
    expect(note.noteId, noteId);
    expect(note.title, '');
    expect(note.content, '');
    expect(note.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(note.updatedAt, note.createdAt);
  });

  test('create generates distinct IDs', () async {
    final firstId = await application.command.createNote();
    final secondId = await application.command.createNote();

    expect(secondId, isNot(firstId));
    expect(
      (await application.query.noteList()).map((note) => note.noteId).toSet(),
      {firstId, secondId},
    );
  });

  test('updates are visible in note and list queries', () async {
    final noteId = await application.command.createNote();

    await application.command.updateNoteTitle(noteId, 'Title');

    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.singleChange('Body'),
    );

    final note = await application.query.note(noteId);
    final list = await application.query.noteList();

    expect(note.title, 'Title');
    expect(note.content, 'Body');
    expect(list.single.title, 'Title');
    expect(list.single.content, 'Body');
  });

  test('trash and restore update list filtering and active count', () async {
    final noteId = await application.command.createNote();
    await application.command.trashNote(noteId);

    final trashedList = await application.query.noteList();
    expect(trashedList, isEmpty);
    expect(
      (await application.query.noteList(
        category: NoteCategory.trashed,
      )).single.noteId,
      noteId,
    );
    expect((await application.query.note(noteId)).isTrashed, isTrue);

    await application.command.restoreNote(noteId);

    final restoredList = await application.query.noteList();
    expect(restoredList, hasLength(1));
    expect(restoredList.single.noteId, noteId);
    expect((await application.query.note(noteId)).isTrashed, isFalse);
  });

  test('list query reflects commands after an earlier read', () async {
    final before = await application.query.noteList();
    final noteId = await application.command.createNote();
    final after = await application.query.noteList();

    expect(before, isEmpty);
    expect(after.map((note) => note.noteId), [noteId]);
  });

  test('list query applies category and sort order', () async {
    await runtime.seedEvents([
      TestEvent(
        actor: 'a',
        stream: 'note/one',
        event: const NoteCreated(noteId: 'one'),
        occuredAt: DateTime.utc(2026, 1, 1),
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/two',
        event: const NoteCreated(noteId: 'two'),
        occuredAt: DateTime.utc(2026, 1, 2),
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/one',
        event: const NoteTrashed(noteId: 'one'),
        occuredAt: DateTime.utc(2026, 1, 3),
      ),
    ]);

    expect((await application.query.noteList()).map((note) => note.noteId), [
      'two',
    ]);
    expect(
      (await application.query.noteList(
        category: NoteCategory.all,
        order: NoteSortOrder.createdAtAscending,
      )).map((note) => note.noteId),
      ['one', 'two'],
    );
    expect(
      (await application.query.noteList(
        category: NoteCategory.all,
        order: NoteSortOrder.createdAtDescending,
      )).map((note) => note.noteId),
      ['two', 'one'],
    );
    expect(
      (await application.query.noteList(
        category: NoteCategory.trashed,
      )).map((note) => note.noteId),
      ['one'],
    );
  });

  test('list query returns current note state without cloning it', () async {
    final noteId = await application.command.createNote();
    final document = CrdtText();
    await application.command.updateNoteTitle(noteId, 'First');
    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.applyChangeToDocument(document, 'First')!,
    );
    final before = await application.query.noteList();

    await application.command.updateNoteTitle(noteId, 'Second');
    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.applyChangeToDocument(document, 'Second')!,
    );
    final after = await application.query.noteList();

    expect(after.single, same(before.single));
    expect(after.single.title, 'Second');
    expect(after.single.content, 'Second');
    expect(before.single.title, 'Second');
    expect(before.single.content, 'Second');
  });

  test('reads existing note events with the registered codecs', () async {
    final createdAt = DateTime.utc(2026, 1, 1);
    final editedAt = DateTime.utc(2026, 1, 2);

    final document = CrdtText();
    final change = CrdtTextTestUtils.applyChangeToDocument(document, 'History');
    expect(change, isNotNull);

    await runtime.seedEvents([
      TestEvent(
        actor: 'a',
        stream: 'note/old',
        event: const NoteCreated(noteId: 'old'),
        occuredAt: createdAt,
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/old',
        event: const NoteTitleUpdated(noteId: 'old', newTitle: 'Existing'),
        occuredAt: editedAt,
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/old',
        event: NoteContentUpdated(noteId: 'old', change: change!),
        occuredAt: editedAt,
      ),
    ]);

    final note = await application.query.note('old');
    final list = await application.query.noteList();

    expect(note.title, 'Existing');
    expect(note.content, 'History');
    expect(note.createdAt, createdAt);
    expect(note.updatedAt, editedAt);
    expect(list.single.title, 'Existing');
  });

  test('crdt text works', () async {
    final time = DateTime.utc(2026, 1, 1);

    final document = CrdtText();
    final change = CrdtTextTestUtils.applyChangeToDocument(document, 'Hello,');
    expect(change, isNotNull);

    await runtime.seedEvents([
      TestEvent(
        actor: 'a',
        stream: 'note/greeting',
        event: const NoteCreated(noteId: 'greeting'),
        occuredAt: time,
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/greeting',
        event: NoteContentUpdated(noteId: 'greeting', change: change!),
        occuredAt: time,
      ),
    ]);

    final note = await application.query.note('greeting');
    expect(note.content, 'Hello,');

    final change2 = CrdtTextTestUtils.applyChangeToDocument(
      document,
      'Hello, CRDT!',
    );
    expect(change2, isNotNull);

    await application.command.updateNoteContent('greeting', change2!);

    final updatedNote = await application.query.note('greeting');
    expect(updatedNote.content, 'Hello, CRDT!');
  });
}
