import 'package:cqrs/cqrs.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class UpdateNoteContentInput {
  final String noteId;
  final String overrideContent;

  const UpdateNoteContentInput({
    required this.noteId,
    required this.overrideContent,
  });

  @override
  String toString() {
    return 'UpdateNoteContentInput{noteId: $noteId, overrideContent: $overrideContent}';
  }
}

class UpdateNoteContent implements Command<UpdateNoteContentInput> {
  const UpdateNoteContent();

  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    await stream.mustExist();

    stream.append(
      NoteContentUpdated(noteId: noteId, newContent: input.overrideContent),
    );

    ctx.logger.debug('note $noteId content updated');
  }
}
