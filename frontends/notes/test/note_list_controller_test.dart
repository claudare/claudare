import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_provider/time_provider.dart';

import 'support/note_list_test_store.dart';

void main() {
  late NotesApp application;
  late NoteListTestStore store;
  late _Clock clock;

  setUp(() {
    store = NoteListTestStore();
    clock = _Clock();
    application = NotesApp(
      cqrsRuntime: CqrsTestRuntime(eventStore: store, timeProvider: clock),
      fts: NoopFts(),
      logger: const NoopLogger(),
    );
  });

  NoteListController createController() {
    final controller = NoteListController(application);
    addTearDown(controller.dispose);
    return controller;
  }

  test('starts loading the note list automatically', () async {
    await application.command.createNote('one');

    final controller = createController();
    final notes = await controller.updates.first;

    expect(notes.single.noteId, 'one');
    expect(controller.value, notes);
  });

  test('a note change emits an updated list', () async {
    final controller = createController();
    await controller.updates.first;
    final updated = controller.updates.firstWhere((notes) => notes.isNotEmpty);

    await application.command.createNote('one');

    expect((await updated).single.noteId, 'one');
  });

  test('moving notes to trash emits their removal from Notes', () async {
    await application.command.createNote('one');
    final controller = createController();
    await controller.updates.first;
    final updated = controller.updates.firstWhere((notes) => notes.isEmpty);

    await controller.deleteNotes(['one']);

    expect(await updated, isEmpty);
  });

  test('category changes emit filtered results without new data', () async {
    await application.command.createNote('active');
    await application.command.createNote('trashed');
    await application.command.trashNote('trashed');
    final controller = createController();
    final updates = StreamIterator(controller.updates);
    addTearDown(updates.cancel);
    expect(await updates.moveNext(), isTrue);
    expect(updates.current.single.noteId, 'active');

    controller.setCategory(NoteCategory.trashed);

    expect(await updates.moveNext(), isTrue);
    expect(updates.current.single.noteId, 'trashed');
    expect(controller.value, updates.current);
  });

  test('order changes emit sorted results without new data', () async {
    await application.command.createNote('one');
    clock.value = DateTime.utc(2026, 2);
    await application.command.createNote('two');
    final controller = createController();
    final updates = StreamIterator(controller.updates);
    addTearDown(updates.cancel);
    expect(await updates.moveNext(), isTrue);
    expect(updates.current.map((note) => note.noteId), ['two', 'one']);

    controller.setOrder(NoteSortOrder.createdAtAscending);

    expect(await updates.moveNext(), isTrue);
    expect(updates.current.map((note) => note.noteId), ['one', 'two']);
    expect(controller.value, updates.current);
  });

  test('initial results use selections made during loading', () async {
    await application.command.createNote('one');
    await application.command.trashNote('one');
    clock.value = DateTime.utc(2026, 2);
    await application.command.createNote('two');
    await application.command.trashNote('two');
    await application.command.createNote('active');
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    store.beforeRead = release.future;
    final controller = createController();
    final initial = controller.updates.first;
    await store.readStarted.future;

    controller.setCategory(NoteCategory.trashed);
    controller.setOrder(NoteSortOrder.createdAtAscending);

    expect(controller.value, isNull);
    release.complete();
    expect((await initial).map((note) => note.noteId), ['one', 'two']);
  });

  test(
    'a late subscriber receives results for the current selection',
    () async {
      await application.command.createNote('one');
      await application.command.trashNote('one');
      final controller = createController();
      expect(await controller.updates.first, isEmpty);

      controller.setCategory(NoteCategory.trashed);

      expect((await controller.updates.first).single.noteId, 'one');
    },
  );

  test(
    'canceling one listener leaves other listeners receiving selections',
    () async {
      await application.command.createNote('one');
      await application.command.trashNote('one');
      final controller = createController();
      final first = StreamIterator(controller.updates);
      final second = StreamIterator(controller.updates);
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      expect(await first.moveNext(), isTrue);
      expect(await second.moveNext(), isTrue);

      await first.cancel();
      controller.setCategory(NoteCategory.trashed);

      expect(await second.moveNext(), isTrue);
      expect(second.current.single.noteId, 'one');
    },
  );

  test('category changes notify listeners synchronously', () {
    final controller = createController();
    final categories = <NoteCategory>[];
    controller.addListener(() => categories.add(controller.category));

    controller.setCategory(NoteCategory.trashed);

    expect(categories, [NoteCategory.trashed]);
  });

  test('selecting the current category does not notify listeners', () {
    final controller = createController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setCategory(NoteCategory.active);

    expect(notifications, 0);
  });

  test('order changes notify listeners synchronously', () {
    final controller = createController();
    final orders = <NoteSortOrder>[];
    controller.addListener(() => orders.add(controller.order));

    controller.setOrder(NoteSortOrder.createdAtAscending);

    expect(orders, [NoteSortOrder.createdAtAscending]);
  });

  test('selecting the current order does not notify listeners', () {
    final controller = createController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setOrder(NoteSortOrder.updatedAtDescending);

    expect(notifications, 0);
  });

  test('live updates retain the selected category and order', () async {
    final controller = createController();
    await controller.updates.first;
    controller.setCategory(NoteCategory.trashed);
    controller.setOrder(NoteSortOrder.createdAtAscending);
    final updated = controller.updates.firstWhere((notes) => notes.isNotEmpty);

    await application.command.createNote('one');
    await application.command.trashNote('one');
    expect((await updated).single.noteId, 'one');

    expect(controller.category, NoteCategory.trashed);
    expect(controller.order, NoteSortOrder.createdAtAscending);
  });

  test('disposing the list stops its live subscription', () async {
    final controller = NoteListController(application);
    await controller.updates.first;
    final closed = expectLater(
      controller.updates,
      emitsInOrder([isA<List<NoteModel>>(), emitsDone]),
    );

    controller.dispose();
    await closed;
    await store.cancelled.future;

    expect(store.activeSubscriptions, 0);
    expect(controller.value, isNull);
  });

  test('disposing during loading closes the list stream', () async {
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    store.beforeRead = release.future;
    final controller = NoteListController(application);
    final closed = expectLater(controller.updates, emitsDone);
    await store.readStarted.future;

    controller.dispose();
    release.complete();
    await closed;
    await store.cancelled.future;

    expect(store.activeSubscriptions, 0);
    expect(controller.value, isNull);
  });

  for (final order in NoteSortOrder.values) {
    test('a new controller defaults to last edited after selecting $order', () {
      final controller = createController();
      controller.setOrder(order);

      final reopened = createController();

      expect(reopened.order, NoteSortOrder.updatedAtDescending);
      expect(reopened.category, NoteCategory.active);
    });
  }
}

class _Clock implements TimeProvider {
  DateTime value = DateTime.utc(2026);

  @override
  DateTime now() => value;
}
