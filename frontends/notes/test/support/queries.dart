import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_app.dart';

Future<NoteModel> readWidgetNote(
  WidgetTester tester,
  NotesApp app,
  String id,
) async => (await tester.runAsync(() => readNote(app, id)))!;

Future<List<NoteModel>> readWidgetNoteList(
  WidgetTester tester,
  NotesApp app,
) async => (await tester.runAsync(() => readNoteList(app)))!;

Future<NoteModel> readNote(NotesApp app, String id) async {
  final live = app.query.liveNote(id);
  try {
    return await live.latest();
  } finally {
    await live.stop();
  }
}

Future<List<NoteModel>> readNoteList(
  NotesApp app, {
  NoteCategory category = NoteCategory.active,
  NoteSortOrder order = NoteSortOrder.createdAtDescending,
}) async {
  final live = app.query.liveNoteList();
  try {
    return (await live.latest()).toSortedList(category: category, order: order);
  } finally {
    await live.stop();
  }
}
