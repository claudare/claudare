import 'package:core/cqrs.dart';
import 'package:core/utils.dart';
import 'package:notes/event/note/_note_codec.dart';
import 'package:notes/event/note/note.dart';
import 'package:notes/stream_id/note_stream_id.dart';

class RestoreNoteInput implements CommandInput {
  final String noteId;

  const RestoreNoteInput({required this.noteId});

  @override
  String get kind => 'restoreNote';

  @override
  encode() {
    return JsonConverter.encode({'noteId': noteId});
  }

  @override
  String toString() {
    return 'RestoreNoteInput{noteId: $noteId}';
  }
}

/// aka "Untrash note"
class RestoreNote implements Command<RestoreNoteInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    final deletedCount = await stream.scan().fold(0, (count, ev) {
      if (ev is NoteTrashed) {
        return count + 1;
      } else if (ev is NoteRestored) {
        return count - 1;
      }
      return count;
    });

    if (deletedCount == 0) {
      return ctx.nack('note was not trashed');
    }
    if (deletedCount > 1) {
      // hhh, this should never happen, why do I check?
      return ctx.nack('note was trashed multiple times');
    }

    stream.append(NoteRestored());
  }
}
