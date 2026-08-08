import 'package:core/cqrs.dart';
import 'package:notes/model/note_data.dart';

// Get and store repo style
abstract interface class NoteProjectionRepo {
  Future<void> reset();

  Future<ProjectionCheckpoint> checkpoint();

  // Future<NoteData?> get(String noteId);

  Future<void> store(NoteData note, int localSequence);

  Future<void> getAndStore(
    String noteId,
    int localSequence,
    NoteData Function(NoteData) update,
  );
}
