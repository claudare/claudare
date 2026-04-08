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

    var exists = false; // Annoying usage in current CQRS design
    var trashed = false;

    await for (final ev in stream.scan()) {
      exists = true;

      switch (ev) {
        case NoteDeleted():
          trashed = true;
          break;
        case NoteRestored():
          trashed = false;
          break;
        default:
          break;
      }
    }

    if (!exists) {
      return ctx.nack('note does not exist');
    }
    if (trashed) {
      return ctx.nack('note already trashed');
    }

    stream.append(NoteDeleted());
  }
}
