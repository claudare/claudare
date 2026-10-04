import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/note/note_controller.dart';

void main() {
  late _FailingStore store;
  late NotesApp application;

  setUp(() {
    store = _FailingStore();
    application = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      idGenerator: IdGeneratorSequential(),
    );
  });

  NoteController controller({String? noteId}) {
    final result = NoteController(application, noteId: noteId);
    addTearDown(result.dispose);
    return result;
  }

  test('draft allocates its permanent ID during construction', () async {
    final ids = IdGeneratorSequential();
    final first = controller();
    final second = controller();
    expect(first.noteId, ids.generateId());
    expect(second.noteId, ids.generateId());
    final document = first.content.document;
    await first.load();
    await first.refresh();
    expect(first.content.document, same(document));
    expect(first.exists, isFalse);
    expect(first.createdAt, isNull);
    expect(first.updatedAt, isNull);
    expect(first.trashedAt, isNull);
  });

  test('empty draft saves write nothing', () async {
    final draft = controller();
    await draft.load();
    expect(await draft.flushChanges(), isFalse);
    expect(await draft.flushChanges(), isFalse);
    expect(store.kinds, isEmpty);
    expect(draft.exists, isFalse);
  });

  test('existing note loads without allocating a draft ID', () async {
    await application.command.createNote('existing');
    await application.command.updateNoteTitle('existing', 'Title');
    final note = controller(noteId: 'existing');
    final loaded = await note.load();
    expect(loaded.title, 'Title');
    expect(note.noteId, 'existing');
    expect(note.exists, isTrue);
    expect(note.createdAt, isNotNull);
    expect(note.updatedAt, note.createdAt);
    expect(await note.flushChanges(), isFalse);
    expect(controller().noteId, IdGeneratorSequential().generateId());
  });

  test('missing existing note cannot be loaded or created by saving', () async {
    final note = controller(noteId: 'missing');
    final notFound = throwsA(
      isA<Exception>().having(
        (error) => error.toString(),
        'message',
        'Exception: Note not found',
      ),
    );
    await expectLater(note.load(), notFound);
    expect(note.isLoading, isFalse);
    expect(note.createdAt, isNull);
    expect(note.updatedAt, isNull);
    expect(note.trashedAt, isNull);
    note.title.value = 'Local title';
    await expectLater(note.flushChanges(), notFound);
    await expectLater(note.refresh(), notFound);
    expect(note.noteId, 'missing');
    expect(store.kinds, isEmpty);
  });

  test('local content survives initial creation and refresh', () async {
    final draft = controller();
    await draft.load();
    final id = draft.noteId;
    final document = draft.content.document;
    draft.content.insert(0, 'Local body');
    draft.title.value = 'Local title';
    await draft.refresh();
    expect(draft.content.text, 'Local body');
    expect(draft.content.hasPendingChanges, isTrue);
    expect(await draft.flushChanges(), isTrue);
    await draft.refresh();
    expect(draft.noteId, id);
    expect(draft.content.document, same(document));
    expect(draft.content.text, 'Local body');
    expect(document.text, 'Local body');
    expect(draft.content.hasPendingChanges, isFalse);
    expect((await application.query.note(id)).title, 'Local title');
    expect(draft.createdAt, isNotNull);
    expect(await draft.flushChanges(), isFalse);
  });

  for (final failure in ['creation', 'refresh after creation']) {
    test(
      '$failure failure retains identity and retries creation once',
      () async {
        final draft = controller();
        await draft.load();
        final id = draft.noteId;
        final document = draft.content.document;
        draft.content.insert(0, 'Body');
        if (failure == 'creation') {
          store.failWrite = true;
        } else {
          store.failReadAfterWrite = true;
        }
        await expectLater(draft.flushChanges(), throwsException);
        expect(draft.noteId, id);
        expect(draft.content.document, same(document));
        expect(draft.content.text, 'Body');
        expect(draft.content.hasPendingChanges, isTrue);
        expect(draft.createdAt, isNull);
        expect(draft.updatedAt, isNull);

        expect(await draft.flushChanges(), isTrue);
        expect(draft.noteId, id);
        expect(draft.exists, isTrue);
        expect(draft.content.hasPendingChanges, isFalse);
        expect((await application.query.note(id)).content, 'Body');
        expect(store.kinds, hasLength(2));
        expect(await application.query.noteList(), hasLength(1));
      },
    );
  }

  test('failed initial loading leaves timestamps safe', () async {
    await application.command.createNote('existing');
    final note = controller(noteId: 'existing');
    store.failRead = true;
    await expectLater(note.load(), throwsException);
    expect(note.isLoading, isFalse);
    expect(note.createdAt, isNull);
    expect(note.updatedAt, isNull);
    expect(note.trashedAt, isNull);
    await note.load();
    expect(note.createdAt, isNotNull);
  });

  test('draft cannot be trashed before persistence', () async {
    await expectLater(controller().trash(), throwsException);
    expect(store.kinds, isEmpty);
  });

  test(
    'title refresh follows persisted updates without writing them back',
    () async {
      await application.command.createNote('existing');
      final note = controller(noteId: 'existing');
      await note.load();
      await application.command.updateNoteTitle('existing', 'Remote');
      expect(await note.flushChanges(), isFalse);
      expect(note.title.value, 'Remote');
      expect(note.title.hasPendingChanges, isFalse);
      expect(store.kinds, hasLength(2));
    },
  );

  test('title refresh preserves unsaved local edits', () async {
    await application.command.createNote('existing');
    final note = controller(noteId: 'existing');
    await note.load();
    note.title.value = 'Z local';
    await application.command.updateNoteTitle('existing', 'Remote');
    await note.refresh();
    expect(note.title.value, 'Z local');
    expect(note.title.document.value, 'Remote');
    expect(await note.flushChanges(), isTrue);
    expect((await application.query.note('existing')).title, 'Z local');
    expect(note.title.hasPendingChanges, isFalse);
  });

  for (final failure in ['write', 'replay']) {
    test('title $failure failure retries without duplicate events', () async {
      await application.command.createNote('existing');
      final note = controller(noteId: 'existing');
      await note.load();
      note.title.value = 'Local';
      store.failWrite = failure == 'write';
      store.failReadAfterWrite = failure == 'replay';
      await expectLater(note.flushChanges(), throwsException);
      expect(note.title.value, 'Local');
      expect(note.title.hasPendingChanges, isTrue);
      expect(await note.flushChanges(), failure == 'write');
      expect(note.title.hasPendingChanges, isFalse);
      expect(store.kinds, hasLength(2));
    });
  }

  test('title edits during a save remain pending for the next save', () async {
    await application.command.createNote('existing');
    final note = controller(noteId: 'existing');
    await note.load();
    note.title.value = 'First';
    final started = Completer<void>();
    final release = Completer<void>();
    store.writeStarted = started;
    store.writeGate = release.future;
    final saving = note.flushChanges();
    await started.future;
    note.title.value = 'Second';
    release.complete();
    await saving;
    expect(note.title.value, 'Second');
    expect(note.title.hasPendingChanges, isTrue);
    expect(await note.flushChanges(), isTrue);
    expect((await application.query.note('existing')).title, 'Second');
    expect(note.title.hasPendingChanges, isFalse);
  });

  test('losing title write adopts the winner without repeated saves', () async {
    await application.command.createNote('existing');
    await application.command.updateNoteTitle('existing', 'Z winner');
    final note = controller(noteId: 'existing');
    await note.load();
    // The static test clock gives both writes the same timestamp and actor.
    note.title.value = 'A loser';
    expect(await note.flushChanges(), isTrue);
    expect(note.title.value, 'Z winner');
    expect(note.title.hasPendingChanges, isFalse);
    expect(await note.flushChanges(), isFalse);
  });

  test('draft cannot be restored before persistence', () async {
    await expectLater(controller().restore(), throwsException);
    expect(store.kinds, isEmpty);
  });

  test('draft skips simulated external edits before persistence', () async {
    await controller().simulateExternalEdit();
    expect(store.kinds, isEmpty);
  });
}

class _FailingStore extends MemoryEventStore {
  final List<String> kinds = [];
  bool failWrite = false;
  bool failRead = false;
  bool failReadAfterWrite = false;
  Completer<void>? writeStarted;
  Future<void>? writeGate;

  @override
  Future<void> saveChanges(changes) async {
    final gate = writeGate;
    writeGate = null;
    writeStarted?.complete();
    writeStarted = null;
    await gate;
    if (failWrite) {
      failWrite = false;
      throw Exception('Interrupted creation');
    }
    await super.saveChanges(changes);
    kinds.addAll(
      changes.events.map<String>((event) => event.encodedEvent.kind),
    );
    if (failReadAfterWrite) {
      failReadAfterWrite = false;
      failRead = true;
    }
  }

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) {
    if (failRead) {
      failRead = false;
      return Future.error(Exception('Interrupted read'));
    }
    return super.getLogEvents(fromPosition);
  }
}
