import 'dart:async';

import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NotesApp application;
  late NoteListController controller;

  setUp(() {
    application = NotesApp(cqrsRuntime: CqrsTestRuntime());
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

  test('category changes filter the current aggregate state', () async {
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
