import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/note/_note_codec.dart';
import 'package:notes_app_v0/event/note/note.dart';
import 'package:notes_app_v0/stream_id/note_stream_id.dart';

class DeleteNoteInput implements CommandInput {
  final String noteId;

  const DeleteNoteInput({required this.noteId});

  @override
  String get kind => 'deleteNote';

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId};
  }

  @override
  String toString() {
    return 'DeleteNoteInput{noteId: $noteId}';
  }
}

class DeleteNote implements Command<DeleteNoteInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    // This implementation is not concurrent, as concurrency will need to use
    // the actual device time.
    // TODO: make this work concurrently, atleast for the title
    // ctx.currentTime() is available in the projection through metadata!
    // With proper merge crdt timestamps will not be needed

    // Rough edges of current CQRS design
    var exists = false;

    await for (final ev in stream.scan()) {
      exists = true;
      if (ev.runtimeType == NoteDeleted) {
        return ctx.nack('note already delete');
      }
    }

    if (!exists) {
      return ctx.nack('note does not exist');
    }

    stream.append(NoteDeleted());
  }
}
