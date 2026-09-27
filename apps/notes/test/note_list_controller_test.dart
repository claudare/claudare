import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/event/note.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:test/test.dart';

void main() {
  late NoteApplication application;
  late NoteListController controller;
  late CqrsTestRuntime runtime;
  late _ControlledEventStore store;
  late bool disposed;

  setUp(() {
    store = _ControlledEventStore();
    runtime = CqrsTestRuntime(eventStore: store);
    application = NoteApplication(cqrsRuntime: runtime);
    controller = NoteListController(application);
    disposed = false;
  });

  void disposeController() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }

  tearDown(() {
    disposeController();
    for (final read in store.reads) {
      read.resume();
    }
  });

  test('initialization loads existing notes', () async {
    await application.command.createNote('existing');

    await controller.initialize();

    expect(controller.noteData.single.noteId, 'existing');
    expect(controller.isLoading, isFalse);
    expect(controller.loadError, isNull);
  });

  test('a local command adds a note without a manual reload', () async {
    await controller.initialize();
    final changed = _until(controller, () => controller.noteData.isNotEmpty);

    await application.command.createNote('new');
    await changed;

    expect(controller.noteData.single.noteId, 'new');
  });

  test('a title update notifies list listeners', () async {
    await application.command.createNote('one');
    await controller.initialize();
    final changed = _until(
      controller,
      () => controller.noteData.single.title == 'Updated',
    );

    await application.command.updateNoteTitle('one', 'Updated');
    await changed;

    expect(controller.noteData.single.title, 'Updated');
  });

  test('deleting notes updates the active category automatically', () async {
    await application.command.createNote('one');
    await controller.initialize();
    await controller.setCategory(NoteCategory.active);
    final changed = _until(controller, () => controller.noteData.isEmpty);

    await controller.deleteNotes(['one']);
    await changed;

    expect(controller.noteData, isEmpty);
  });

  test('category changes query the selected category', () async {
    final activeId = application.generateNoteId();
    await application.command.createNote(activeId);
    final trashedId = application.generateNoteId();
    await application.command.createNote(trashedId);
    await application.command.trashNote(trashedId);
    await controller.initialize();
    await _settle();
    final reads = store.logReads;

    await controller.setCategory(NoteCategory.active);
    expect(controller.noteData.map((note) => note.noteId), [activeId]);

    await controller.setCategory(NoteCategory.trashed);
    expect(controller.noteData.map((note) => note.noteId), [trashedId]);
    expect(store.logReads, greaterThan(reads));
  });

  test('sort changes query the selected order', () async {
    await runtime.seedEvents([
      TestEvent(
        actor: 'seed',
        stream: 'note/one',
        event: const NoteCreated(noteId: 'one'),
        occuredAt: DateTime.utc(2026, 1, 1),
      ),
      TestEvent(
        actor: 'seed',
        stream: 'note/two',
        event: const NoteCreated(noteId: 'two'),
        occuredAt: DateTime.utc(2026, 1, 2),
      ),
    ]);
    await controller.initialize();
    await _settle();
    final reads = store.logReads;
    expect(controller.noteData.map((note) => note.noteId), ['two', 'one']);

    await controller.setOrder(NoteSortOrder.createdAtAscending);

    expect(controller.noteData.map((note) => note.noteId), ['one', 'two']);
    expect(store.logReads, greaterThan(reads));
  });

  test('disposal stops resolution after later commands', () async {
    await controller.initialize();
    await _settle();
    final reads = store.logReads;
    disposeController();

    await application.command.createNote('after-dispose');
    await _settle();

    expect(store.logReads, reads);
    expect(controller.noteData, isEmpty);
  });

  test(
    'disposal during initialization cancels the notification listener',
    () async {
      final read = store.pauseNextRead();
      var notifications = 0;
      controller.addListener(() => notifications++);
      final initialization = controller.initialize();
      await read.entered.future;
      final beforeDispose = notifications;
      disposeController();

      read.resume();
      await initialization;
      await application.command.createNote('after-dispose');
      await _settle();

      expect(store.logReads, 1);
      expect(notifications, beforeDispose);
      expect(controller.noteData, isEmpty);
    },
  );

  test('disposal suppresses updates from an in-flight resolve', () async {
    await controller.initialize();
    await _settle();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final read = store.pauseNextRead();
    await application.command.createNote('in-flight');
    await read.entered.future;
    final beforeDispose = notifications;

    disposeController();
    read.resume();
    await _settle();

    expect(notifications, beforeDispose);
    expect(controller.noteData, isEmpty);
  });

  test('initial resolve exceptions are exposed as load errors', () async {
    final failure = Exception('initial read failed');
    store.nextFailure = failure;

    await controller.initialize();

    expect(controller.loadError, same(failure));
    expect(controller.isLoading, isFalse);
  });

  test('initial programmer errors reach the caller', () async {
    final failure = StateError('initial read failed');
    store.nextFailure = failure;

    await expectLater(controller.initialize(), throwsA(same(failure)));

    expect(controller.loadError, isNull);
  });

  test('refetch exceptions are exposed as load errors', () async {
    await controller.initialize();
    await _settle();
    final failure = Exception('later read failed');
    store.nextFailure = failure;
    final failed = _until(controller, () => controller.loadError != null);

    await application.command.createNote('one');
    await failed;

    expect(controller.loadError, same(failure));
    expect(controller.noteData, isEmpty);
  });

  test('a later notification recovers the list and clears its error', () async {
    await controller.initialize();
    await _settle();
    store.nextFailure = Exception('later read failed');
    final failed = _until(controller, () => controller.loadError != null);
    await application.command.createNote('one');
    await failed;
    final recovered = _until(controller, () => controller.noteData.length == 2);

    await application.command.createNote('two');
    await recovered;

    expect(controller.noteData.map((note) => note.noteId), ['one', 'two']);
    expect(controller.loadError, isNull);
  });

  test(
    'notifications during the initial query trigger one trailing query',
    () async {
      final read = store.pauseNextRead();
      final initialization = controller.initialize();
      await read.entered.future;

      await application.command.createNote('during-query');
      runtime.notificationBus.notify('note/during-query');
      runtime.notificationBus.notify('note/during-query');
      await _settle();
      read.resume();
      await initialization;

      expect(controller.noteData.single.noteId, 'during-query');
      expect(store.logReads, 3);
    },
  );

  test('manual reload queries data without a notification', () async {
    await controller.initialize();
    await runtime.seedEvents([
      TestEvent(
        actor: 'seed',
        stream: 'note/seeded',
        event: const NoteCreated(noteId: 'seeded'),
        occuredAt: DateTime.utc(2026),
      ),
    ]);
    expect(controller.noteData, isEmpty);

    await controller.reloadNotes();

    expect(controller.noteData.single.noteId, 'seeded');
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<void> _until(NoteListController controller, bool Function() condition) {
  if (condition()) return Future<void>.value();
  final completed = Completer<void>();
  void onChanged() {
    if (!condition()) return;
    controller.removeListener(onChanged);
    completed.complete();
  }

  controller.addListener(onChanged);
  addTearDown(() => controller.removeListener(onChanged));
  return completed.future;
}

final class _ControlledEventStore extends MemoryEventStore {
  final reads = <_ReadGate>[];
  var logReads = 0;
  Object? nextFailure;
  _ReadGate? _nextRead;

  _ReadGate pauseNextRead() {
    final read = _ReadGate();
    _nextRead = read;
    reads.add(read);
    return read;
  }

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) async {
    logReads++;
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    final read = _nextRead;
    _nextRead = null;
    final result = await super.getLogEvents(fromPosition);
    if (read != null) {
      read.entered.complete();
      await read.released.future;
    }
    return result;
  }
}

final class _ReadGate {
  final entered = Completer<void>();
  final released = Completer<void>();

  void resume() {
    if (!released.isCompleted) released.complete();
  }
}
