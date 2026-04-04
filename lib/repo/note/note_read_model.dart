import 'package:notes_app_v0/model/note_data.dart';

abstract interface class NoteReadModel {
  Future<NoteData?> getNote(String noteId);

  // TODO: this needs to have a more advanced query capabilities:
  // isDeleted boolean
  // favorite filtering
  // ordering by: createdAt ASC DESC, updatedAt ASC DESC
  Future<List<NoteData>> getAllNonDeletedNotes();
}
