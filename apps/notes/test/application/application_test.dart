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

  test('returns null for a note that was never created', () async {
    expect(await application.query.note('missing'), isNull);
    expect((await application.query.noteList()).notes, isEmpty);
  });

  test('create generates a usable note ID', () async {
    final noteId = await application.command.createNote();

    expect(noteId, hasLength(IdGenerator.stringLength));
    final note = await application.query.note(noteId);
    expect(note, isNotNull);
    expect(note!.noteId, noteId);
    expect(note.title, '');
    expect(note.content, '');
    expect(note.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(note.updatedAt, note.createdAt);
  });

  test('create generates distinct IDs', () async {
    final firstId = await application.command.createNote();
    final secondId = await application.command.createNote();

    expect(secondId, isNot(firstId));
    expect((await application.query.noteList()).notes.keys, {
      firstId,
      secondId,
    });
  });

  test('updates are visible in note and list queries', () async {
    final noteId = await application.command.createNote();

    await application.command.updateNoteTitle(noteId, 'Title');

    await application.command.updateNoteContent(
      noteId,
      testCrdtTextSingleChange('Body'),
    );

    final note = await application.query.note(noteId);
    final list = await application.query.noteList();

    expect(note!.title, 'Title');
    expect(note.content, 'Body');
    expect(list.notes[noteId]!.title, 'Title');
    expect(list.notes[noteId]!.content, 'Body');
  });

  test('trash and restore update list filtering and active count', () async {
    final noteId = await application.command.createNote();
    await application.command.trashNote(noteId);

    final trashedList = await application.query.noteList();
    expect(trashedList.activeCount, 0);
    expect(trashedList.toSortedList(), isEmpty);
    expect(
      trashedList.toSortedList(category: NoteCategory.trashed).single.noteId,
      noteId,
    );
    expect((await application.query.note(noteId))!.isTrashed, isTrue);

    await application.command.restoreNote(noteId);

    final restoredList = await application.query.noteList();
    expect(restoredList.activeCount, 1);
    expect(restoredList.toSortedList().single.noteId, noteId);
    expect((await application.query.note(noteId))!.isTrashed, isFalse);
  });

  test('list query reflects commands after an earlier read', () async {
    final before = await application.query.noteList();
    final noteId = await application.command.createNote();
    final after = await application.query.noteList();

    expect(before.notes, isEmpty);
    expect(after.notes.keys, [noteId]);
  });

  test('reads existing note events with the registered codecs', () async {
    final createdAt = DateTime.utc(2026, 1, 1);
    final editedAt = DateTime.utc(2026, 1, 2);

    final document = CrdtText();
    final change = testCrdtTextApplyChangeToDocument(document, 'History');
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

    expect(note!.title, 'Existing');
    expect(note.content, 'History');
    expect(note.createdAt, createdAt);
    expect(note.updatedAt, editedAt);
    expect(list.notes['old']!.title, 'Existing');
  });

  test('crdt text works', () async {
    final time = DateTime.utc(2026, 1, 1);

    final document = CrdtText();
    final change = testCrdtTextApplyChangeToDocument(document, 'Hello,');
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
    expect(note!.content, 'Hello,');

    final change2 = testCrdtTextApplyChangeToDocument(document, 'Hello, CRDT!');
    expect(change2, isNotNull);

    await application.command.updateNoteContent('greeting', change2!);

    final updatedNote = await application.query.note('greeting');
    expect(updatedNote!.content, 'Hello, CRDT!');
  });
}
