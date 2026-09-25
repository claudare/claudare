import 'package:cqrs/cqrs.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class UpdateNoteContent implements Command {
  final String noteId;
  final String overrideContent;

  const UpdateNoteContent({
    required this.noteId,
    required this.overrideContent,
  });

  @override
  String toString() {
    return 'UpdateNoteContent{noteId: $noteId, overrideContent: $overrideContent}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    await stream.mustExist();

    stream.append(
      NoteContentUpdated(noteId: noteId, newContent: overrideContent),
    );

    ctx.logger.debug('note $noteId content updated');
  }
}
