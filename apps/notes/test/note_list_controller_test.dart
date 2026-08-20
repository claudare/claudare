import 'dart:async';

import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/command/create_note.dart';
import 'package:notes/screens/home/note_list_controller.dart';
import 'package:test/test.dart';

void main() {
  test('resolved-note projection updates reload the note list', () async {
    final application = await _application();
    final controller = NoteListController(application);
    addTearDown(() async {
      controller.dispose();
      await application.close();
    });
    final loaded = Completer<void>();
    controller.addListener(() {
      if (controller.noteData.map((note) => note.noteId).contains('note-1') &&
          !loaded.isCompleted) {
        loaded.complete();
      }
    });

    await application.commandExecute(
      const CreateNote(),
      const CreateNoteInput(noteId: 'note-1'),
    );
    await application.pump();
    await loaded.future.timeout(const Duration(seconds: 2));

    expect(controller.noteData.map((note) => note.noteId), contains('note-1'));
  });

  test('notifications during reload request one trailing reload', () async {
    final application = await _application();
    final controller = NoteListController(application);
    addTearDown(() async {
      controller.dispose();
      await application.close();
    });
    var loadingStarts = 0;
    var sentOverlappingNotifications = false;
    controller.addListener(() {
      if (!controller.isLoading) return;
      loadingStarts++;
      if (sentOverlappingNotifications) return;
      sentOverlappingNotifications = true;
      application.resolvedNoteReadModelNotifier
        ..notifyChanged()
        ..notifyChanged();
    });

    await controller.reloadNotes();

    expect(loadingStarts, 2);
  });

  test('disposing removes the read-model listener', () async {
    final application = await _application();
    final controller = NoteListController(application);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.dispose();
    application.resolvedNoteReadModelNotifier.notifyChanged();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 0);
    await application.close();
  });
}

Future<NoteApplication> _application() async {
  final application = NoteApplication.test();
  await application.initialize(
    notesDbFilepath: IsolateSqlite.memoryFilename,
    searchDbFilepath: IsolateSqlite.memoryFilename,
  );
  return application;
}
