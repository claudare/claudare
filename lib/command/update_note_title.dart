import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/note/_note_codec.dart';
import 'package:notes_app_v0/event/note/note.dart';
import 'package:notes_app_v0/stream_id/note_stream_id.dart';

class UpdateNoteTitleInput implements CommandInput {
  final String noteId;
  final String fullValue;

  const UpdateNoteTitleInput({required this.noteId, required this.fullValue});

  @override
  String get kind => 'updateNoteTitle';

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId, 'fullValue': fullValue};
  }
}

class UpdateNoteTitle implements Command<UpdateNoteTitleInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    // This implementation is not concurrent, as concurrency will need to use
    // the actual device time.
    // TODO: make this work concurrently, as title will NOT be a CRDT.
    // ctx.currentTime() is available in the projection through metadata!

    await stream.mustExist();

    stream.append(NoteTitleUpdated(noteId: noteId, newTitle: input.fullValue));
  }
}
