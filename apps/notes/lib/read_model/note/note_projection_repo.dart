import 'package:notes/read_model/note/note_data.dart';

abstract interface class NoteProjectionRepo {
  Future<void> reset();

  Future<void> store(NoteData note);

  Future<void> getAndStore(String noteId, NoteData Function(NoteData) update);
}
