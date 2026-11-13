import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:crdt/crdt_text.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:test/test.dart';

import '../support/queries.dart';

void main() {
  late CqrsTestRuntime runtime;
  late NotesApp application;

  setUp(() {
    runtime = CqrsTestRuntime();
    application = NotesApp(
      cqrsRuntime: runtime,
      fts: NoopFts(),
      logger: const NoopLogger(),
    );
  });

  test('returns absent state for a note that was never created', () async {
    expect((await readNote(application, 'missing')).exists, isFalse);
    expect(await readNoteList(application), isEmpty);
  });

  test('create generates a usable note ID', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);

    expect(
      noteId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    final note = await readNote(application, noteId);
    expect(note.exists, isTrue);
    expect(note.noteId, noteId);
    expect(note.title, '');
    expect(note.content, '');
    expect(note.createdAt, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(note.updatedAt, note.createdAt);
  });

  test('create generates distinct IDs', () async {
    final firstId = application.generateNoteId();
    await application.command.createNote(firstId);
    final secondId = application.generateNoteId();
    await application.command.createNote(secondId);

    expect(secondId, isNot(firstId));
    expect(
      (await readNoteList(application)).map((note) => note.noteId).toSet(),
      {firstId, secondId},
    );
  });

  test('updates are visible in note and list queries', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);

    await application.command.updateNoteTitle(noteId, 'Title');

    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.singleChange('Body'),
    );

    final note = await readNote(application, noteId);
    final list = await readNoteList(application);

    expect(note.title, 'Title');
    expect(note.content, 'Body');
    expect(list.single.title, 'Title');
    expect(list.single.content, 'Body');
  });

  test('trash and restore update list filtering and active count', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    await application.command.trashNote(noteId);

    final trashedList = await readNoteList(application);
    expect(trashedList, isEmpty);
    expect(
      (await readNoteList(
        application,
        category: NoteCategory.trashed,
      )).single.noteId,
      noteId,
    );
    expect((await readNote(application, noteId)).isTrashed, isTrue);

    await application.command.restoreNote(noteId);

    final restoredList = await readNoteList(application);
    expect(restoredList, hasLength(1));
    expect(restoredList.single.noteId, noteId);
    expect((await readNote(application, noteId)).isTrashed, isFalse);
  });

  test('list query reflects commands after an earlier read', () async {
    final before = await readNoteList(application);
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    final after = await readNoteList(application);

    expect(before, isEmpty);
    expect(after.map((note) => note.noteId), [noteId]);
  });

  test('list query applies category and sort order', () async {
    await runtime.seedEvents([
      TestEvent(
        actor: 'a',
        stream: 'note/one',
        event: const NoteCreated(),
        occuredAt: DateTime.utc(2026, 1, 1),
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/two',
        event: const NoteCreated(),
        occuredAt: DateTime.utc(2026, 1, 2),
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/one',
        event: const NoteTrashed(),
        occuredAt: DateTime.utc(2026, 1, 3),
      ),
    ]);

    expect((await readNoteList(application)).map((note) => note.noteId), [
      'two',
    ]);
    expect(
      (await readNoteList(
        application,
        category: NoteCategory.all,
        order: NoteSortOrder.createdAtAscending,
      )).map((note) => note.noteId),
      ['one', 'two'],
    );
    expect(
      (await readNoteList(
        application,
        category: NoteCategory.all,
        order: NoteSortOrder.createdAtDescending,
      )).map((note) => note.noteId),
      ['two', 'one'],
    );
    expect(
      (await readNoteList(
        application,
        category: NoteCategory.trashed,
      )).map((note) => note.noteId),
      ['one'],
    );
  });

  test('live list updates the existing note model', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    final document = CrdtText();
    await application.command.updateNoteTitle(noteId, 'First');
    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.applyChangeToDocument(document, 'First')!,
    );
    final live = application.query.liveNoteList();
    addTearDown(live.stop);
    final model = await live.latest();
    final before = model.toSortedList();

    await application.command.updateNoteTitle(noteId, 'Second');
    await application.command.updateNoteContent(
      noteId,
      CrdtTextTestUtils.applyChangeToDocument(document, 'Second')!,
    );
    await live.latest();
    final after = model.toSortedList();

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
        event: const NoteCreated(),
        occuredAt: createdAt,
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/old',
        event: const NoteTitleUpdated(newTitle: 'Existing'),
        occuredAt: editedAt,
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/old',
        event: NoteContentUpdated(change: change!),
        occuredAt: editedAt,
      ),
    ]);

    final note = await readNote(application, 'old');
    final list = await readNoteList(application);

    expect(note.title, 'Existing');
    expect(note.content, 'History');
    expect(note.createdAt, createdAt);
    expect(note.updatedAt, editedAt);
    expect(list.single.title, 'Existing');
  });

  test('statistics excludes trashed notes', () async {
    await application.command.createNote('one');
    await application.command.createNote('two');
    await application.command.trashNote('one');

    expect((await application.query.statistics()).activeCount, 1);
  });

  test('statistics includes restored notes', () async {
    await application.command.createNote('one');
    await application.command.trashNote('one');
    await application.command.restoreNote('one');

    expect((await application.query.statistics()).activeCount, 1);
  });

  test('permanent deletion removes the note from live lists', () async {
    await application.command.createNote('one');
    await application.command.createNote('two');
    final live = application.query.liveNoteList();
    addTearDown(live.stop);
    final model = await live.latest();

    await runtime.execute(const _DeleteNote('one'));
    await live.latest();

    expect(model.toSortedList().single.noteId, 'two');
    expect(model.activeCount, 1);
  });

  test('permanent deletion removes the note from statistics', () async {
    await application.command.createNote('one');
    await application.command.createNote('two');

    await runtime.execute(const _DeleteNote('one'));

    expect((await application.query.statistics()).activeCount, 1);
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
        event: const NoteCreated(),
        occuredAt: time,
      ),
      TestEvent(
        actor: 'a',
        stream: 'note/greeting',
        event: NoteContentUpdated(change: change!),
        occuredAt: time,
      ),
    ]);

    final note = await readNote(application, 'greeting');
    expect(note.content, 'Hello,');

    final change2 = CrdtTextTestUtils.applyChangeToDocument(
      document,
      'Hello, CRDT!',
    );
    expect(change2, isNotNull);

    await application.command.updateNoteContent('greeting', change2!);

    final updatedNote = await readNote(application, 'greeting');
    expect(updatedNote.content, 'Hello, CRDT!');
  });
}

class _DeleteNote implements Command {
  final String id;

  const _DeleteNote(this.id);

  @override
  Future<void> handle(CommandContextApi ctx) => ctx.stream('note/$id').delete();
}
