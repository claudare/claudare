import 'dart:async';

import 'package:cqrs/cqrs_test_utils.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:test/test.dart';

void main() {
  late NoteApplication application;
  late NoteListController controller;

  setUp(() {
    application = NoteApplication(cqrsRuntime: CqrsTestRuntime());
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

  test('deleting notes refreshes their trashed state', () async {
    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    await controller.reloadNotes();

    await controller.deleteNotes([noteId]);

    expect(controller.noteData.single.noteId, noteId);
    expect(controller.noteData.single.isTrashed, isTrue);
  });

  test('category changes filter the current aggregate state', () async {
    final activeId = application.generateNoteId();
    await application.command.createNote(activeId);
    final trashedId = application.generateNoteId();
    await application.command.createNote(trashedId);
    await application.command.trashNote(trashedId);

    await controller.setCategory(NoteCategory.active);
    expect(controller.noteData.map((note) => note.noteId), [activeId]);

    await controller.setCategory(NoteCategory.trashed);
    expect(controller.noteData.map((note) => note.noteId), [trashedId]);
  });
}
