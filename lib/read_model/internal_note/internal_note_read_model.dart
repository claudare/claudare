import 'package:notes_app_v0/model/note_data.dart';

abstract interface class InternalNoteReadModel {
  // TODO: should this be nullable? How to handle these issues?
  // The UI could become out of date, maybe?
  Future<NoteData> getNote(String noteId);
}
