import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/note/_note_codec.dart';
import 'package:notes_app_v0/event/note/note.dart';
import 'package:notes_app_v0/stream_id/note_stream_id.dart';

class UpdateNoteContentInput implements CommandInput {
  final String noteId;
  final String overrideContent;

  const UpdateNoteContentInput({
    required this.noteId,
    required this.overrideContent,
  });

  @override
  String get kind => 'updateNoteContent';

  @override
  Map<String, dynamic> toJson() {
    return {'noteId': noteId, 'overrideContent': overrideContent};
  }

  @override
  String toString() {
    return 'UpdateNoteContentInput{noteId: $noteId, overrideContent: $overrideContent}';
  }
}

class UpdateNoteContent implements Command<UpdateNoteContentInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    // This implementation is not concurrent, as concurrency will need to use
    // the actual device time.
    // TODO: make this work concurrently, atleast for the title
    // ctx.currentTime() is available in the projection through metadata!
    // With proper merge crdt timestamps will not be needed

    await stream.mustExist();

    stream.append(
      NoteContentUpdated(noteId: noteId, newContent: input.overrideContent),
    );
  }
}
