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

  test('reload reads notes created by a local command', () async {
    await controller.reloadNotes();
    final noteId = await application.command.createNote();

    expect(controller.noteData, isEmpty);

    await controller.reloadNotes();

    expect(controller.noteData.map((note) => note.noteId), [noteId]);
  });

  test('deleting notes refreshes their trashed state', () async {
    final noteId = await application.command.createNote();
    await controller.reloadNotes();

    await controller.deleteNotes([noteId]);

    expect(controller.noteData.single.noteId, noteId);
    expect(controller.noteData.single.isTrashed, isTrue);
  });

  test('category changes filter the current aggregate state', () async {
    final activeId = await application.command.createNote();
    final trashedId = await application.command.createNote();
    await application.command.trashNote(trashedId);

    await controller.setCategory(NoteCategory.active);
    expect(controller.noteData.map((note) => note.noteId), [activeId]);

    await controller.setCategory(NoteCategory.trashed);
    expect(controller.noteData.map((note) => note.noteId), [trashedId]);
  });
}
