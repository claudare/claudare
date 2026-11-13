import 'package:notes_app/notes_app.dart';

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
