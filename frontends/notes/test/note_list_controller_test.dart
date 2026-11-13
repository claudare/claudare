import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NotesApp application;
  late NoteListController controller;
  late _ListStore store;

  setUp(() {
    store = _ListStore();
    application = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store),
      fts: NoopFts(),
      logger: const NoopLogger(),
    );
    controller = NoteListController(application);
  });

  tearDown(() => controller.dispose());

  test('a note change refreshes the list automatically', () async {
    await controller.reloadNotes();
    final noteId = application.generateNoteId();
    final updated = Completer<void>();
    controller.addListener(() {
      if (!updated.isCompleted &&
          controller.noteData.any((note) => note.noteId == noteId)) {
        updated.complete();
      }
    });
    await application.command.createNote(noteId);
    await updated.future;

    expect(controller.noteData.map((note) => note.noteId), [noteId]);
  });

  test('moving notes to trash removes them from Notes', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    await controller.reloadNotes();

    await controller.deleteNotes([noteId]);

    expect(controller.noteData, isEmpty);
  });

  test('category changes filter the current projection model', () async {
    final activeId = application.generateNoteId();
    await application.command.createNote(activeId);
    final trashedId = application.generateNoteId();
    await application.command.createNote(trashedId);
    await application.command.trashNote(trashedId);

    await controller.reloadNotes();
    expect(controller.noteData.map((note) => note.noteId), [activeId]);

    await controller.setCategory(NoteCategory.trashed);
    expect(controller.noteData.map((note) => note.noteId), [trashedId]);
  });

  test('switching categories clears the previous list immediately', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    await controller.reloadNotes();

    final switching = controller.setCategory(NoteCategory.trashed);
    expect(controller.noteData, isEmpty);
    await switching;
    expect(controller.noteData, isEmpty);
  });

  test('live updates retain the selected category and order', () async {
    await controller.reloadNotes();
    await controller.setCategory(NoteCategory.trashed);
    await controller.setOrder(NoteSortOrder.createdAtAscending);
    final updated = Completer<void>();
    controller.addListener(() {
      if (controller.noteData.isNotEmpty && !updated.isCompleted) {
        updated.complete();
      }
    });

    await application.command.createNote('one');
    await application.command.trashNote('one');
    await updated.future;

    expect(controller.noteData.single.noteId, 'one');
    expect(controller.category, NoteCategory.trashed);
    expect(controller.order, NoteSortOrder.createdAtAscending);
  });

  test(
    'initial replay keeps loading visible until the model is ready',
    () async {
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      store.beforeRead = release.future;

      final loading = controller.reloadNotes();
      await store.readStarted.future;
      expect(controller.isLoading, isTrue);
      expect(controller.noteData, isEmpty);
      release.complete();
      await loading;

      expect(controller.isLoading, isFalse);
      expect(controller.loadError, isNull);
    },
  );

  test('initial replay failure is exposed through the list error', () async {
    final error = Exception('Read failed');
    store.readFailure = error;

    await controller.reloadNotes();

    expect(controller.loadError, same(error));
    expect(controller.isLoading, isFalse);
    expect(controller.noteData, isEmpty);
  });

  test('live replay failure is exposed through the list error', () async {
    await controller.reloadNotes();
    final error = Exception('Read failed');
    final failed = Completer<void>();
    controller.addListener(() {
      if (controller.loadError != null && !failed.isCompleted) {
        failed.complete();
      }
    });
    store.readFailure = error;

    await application.command.createNote('one');
    await failed.future;

    expect(controller.loadError, same(error));
    expect(controller.isLoading, isFalse);
  });

  test('disposing the list stops its live subscription', () async {
    final other = NoteListController(application);
    await other.reloadNotes();
    var notifications = 0;
    other.addListener(() => notifications++);

    other.dispose();
    await store.cancelled.future;
    await application.command.createNote('one');

    expect(store.activeSubscriptions, 0);
    expect(notifications, 0);
    expect(other.noteData, isEmpty);
  });

  for (final order in NoteSortOrder.values) {
    test(
      'a new controller defaults to last edited after selecting $order',
      () async {
        await controller.reloadNotes();
        await controller.setOrder(order);
        final reopened = NoteListController(application);
        addTearDown(reopened.dispose);
        await reopened.reloadNotes();
        expect(reopened.order, NoteSortOrder.updatedAtDescending);
        expect(reopened.category, NoteCategory.active);
      },
    );
  }
}

class _ListStore extends MemoryEventStore {
  final cancelled = Completer<void>();
  final readStarted = Completer<void>();
  int activeSubscriptions = 0;
  Future<void>? beforeRead;
  Exception? readFailure;

  @override
  Stream<EventChange> get eventChanges => Stream.multi((controller) {
    activeSubscriptions++;
    final subscription = super.eventChanges.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () async {
      await subscription.cancel();
      activeSubscriptions--;
      if (!cancelled.isCompleted) cancelled.complete();
    };
  });

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  ) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await beforeRead;
    if (readFailure != null) throw readFailure!;
    return super.getLogEvents(filter, fromPosition);
  }
}
