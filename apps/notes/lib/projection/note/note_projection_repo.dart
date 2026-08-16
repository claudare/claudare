import 'package:notes/model/note_data.dart';

// Get and store repo style
abstract interface class NoteProjectionRepo {
  Future<void> reset();

  Future<void> store(NoteData note);

  Future<void> getAndStore(String noteId, NoteData Function(NoteData) update);
}
