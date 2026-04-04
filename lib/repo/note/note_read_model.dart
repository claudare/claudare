import 'package:notes_app_v0/model/note_data.dart';

abstract interface class NoteReadModel {
  Future<NoteData?> getNote(String noteId);

  Future<List<NoteData>> getAllNotes();

  Future<List<NoteData>> getAllDeletedNotes();
}
