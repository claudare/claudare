import 'package:core/cqrs.dart';
import 'package:core/utils.dart';
import 'package:notes/event/note/_note_codec.dart';
import 'package:notes/event/note/note.dart';
import 'package:notes/stream_id/note_stream_id.dart';

class TrashNoteInput implements CommandInput {
  final String noteId;

  const TrashNoteInput({required this.noteId});

  @override
  String get kind => 'deleteNote';

  @override
  encode() {
    return JsonConverter.encode({'noteId': noteId});
  }

  @override
  String toString() {
    return 'TrashNoteInput{noteId: $noteId}';
  }
}

class TrashNote implements Command<TrashNoteInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    var exists = false; // Annoying usage in current CQRS design
    var trashed = false;

    await for (final ev in stream.scan()) {
      exists = true;

      switch (ev) {
        case NoteTrashed():
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

    stream.append(NoteTrashed());
  }
}
