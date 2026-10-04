import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/note/note_controller.dart';

void main() {
  test('refresh advances past non-content events and empty reads', () async {
    final store = _ObservedStore();
    final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
    final id = app.generateNoteId();
    await app.command.createNote(id);
    final controller = NoteController(app, noteId: id);
    addTearDown(controller.dispose);
    await controller.load();
    await app.command.updateNoteTitle(id, 'Title');
    await app.command.trashNote(id);
    store.reads.clear();
    await controller.refresh();
    expect(store.reads.first, 1);
    expect(controller.isTrashed, isTrue);
    store.reads.clear();
    await controller.refresh();
    await controller.refresh();
    expect(store.reads, [3, 3]);
    expect(controller.content.prepareChange(), isNull);
  });

  test(
    'refresh merges persisted content into the retained local draft',
    () async {
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime());
      final id = app.generateNoteId();
      await app.command.createNote(id);
      final controller = NoteController(app, noteId: id);
      addTearDown(controller.dispose);
      await controller.load();
      final document = controller.content.document;
      controller.content.insert(0, 'Body');
      expect(document.text, '');
      await controller.flushChanges();
      expect(document.text, 'Body');
      expect(controller.content.hasPendingChanges, isFalse);

      controller.content.insert(0, 'Local ');
      final pending = controller.content.prepareChange();
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        ' remote',
        actorId: 'remote',
      );
      expect(document.text, 'Body');
      await controller.refresh();
      expect(controller.content.document, same(document));
      expect(document.text, 'Body remote');
      expect(controller.content.text, 'Local Body remote');
      expect(controller.content.prepareChange(), same(pending));
    },
  );

  test(
    'a saved batch stays pending until a failed refresh is retried',
    () async {
      final store = _ObservedStore();
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
      final id = app.generateNoteId();
      await app.command.createNote(id);
      final controller = NoteController(app, noteId: id);
      addTearDown(controller.dispose);
      await controller.load();
      controller.content.insert(0, 'Body');
      final prepared = controller.content.prepareChange();
      store.failReadAfterWrite = true;
      await expectLater(controller.flushChanges(), throwsException);
      expect((await app.query.note(id)).content, 'Body');
      expect(controller.content.document.text, '');
      expect(controller.content.prepareChange(), same(prepared));
      final writes = store.writes;

      expect(await controller.flushChanges(), isFalse);
      expect(store.writes, writes);
      expect(controller.content.document.text, 'Body');
      expect(controller.content.hasPendingChanges, isFalse);
    },
  );

  test(
    'refresh retries editor notification after document application',
    () async {
      final store = _ObservedStore();
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
      final id = app.generateNoteId();
      await app.command.createNote(id);
      final controller = NoteController(app, noteId: id);
      addTearDown(controller.dispose);
      await controller.load();
      var fail = true;
      final observed = <String>[];
      controller.content.addListener(() {
        if (fail) throw StateError('Editor notification interrupted');
        observed.add(controller.content.text);
      });
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        'Body',
        actorId: 'remote',
      );
      await expectLater(controller.refresh(), throwsStateError);
      expect(controller.content.document.text, 'Body');
      fail = false;
      store.reads.clear();
      await controller.refresh();
      expect(store.reads.first, 1);
      expect(observed, ['Body']);
      await controller.refresh();
      expect(observed, ['Body']);
    },
  );

  test(
    'refresh resumes after the last successfully delivered event on failure',
    () async {
      final store = _ObservedStore();
      final app = NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: store));
      final id = app.generateNoteId();
      await app.command.createNote(id);
      final controller = NoteController(app, noteId: id);
      addTearDown(controller.dispose);
      await controller.load();
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        'One',
        actorId: 'remote',
      );
      await app.command.testSimulateExternalNoteContentAppend(
        id,
        ' two',
        actorId: 'remote',
      );
      store.failAt = 2;
      await expectLater(controller.refresh(), throwsException);
      expect(controller.content.text, 'One');
      store.reads.clear();
      await controller.refresh();
      expect(store.reads.first, 2);
      expect(controller.content.text, 'One two');
      expect(controller.content.prepareChange(), isNull);
    },
  );
}

class _ObservedStore extends MemoryEventStore {
  final List<int> reads = [];
  int? failAt;
  int writes = 0;
  bool failReadAfterWrite = false;
  bool _failNextRead = false;

  _ObservedStore() : super(eventFetchPageSize: 1);

  @override
  Future<void> saveChanges(changes) async {
    await super.saveChanges(changes);
    writes++;
    if (failReadAfterWrite) {
      failReadAfterWrite = false;
      _failNextRead = true;
    }
  }

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) {
    reads.add(fromPosition);
    if (failAt == fromPosition || _failNextRead) {
      failAt = null;
      _failNextRead = false;
      return Future.error(Exception('Interrupted event read'));
    }
    return super.getLogEvents(fromPosition);
  }
}
