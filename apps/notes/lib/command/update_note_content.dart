import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class UpdateNoteContent implements Command {
  final String noteId;
  final CrdtTextChange change;

  const UpdateNoteContent({required this.noteId, required this.change});

  @override
  String toString() {
    return 'UpdateNoteContent{noteId: $noteId, change: $change}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    await stream.mustExist();

    stream.append(NoteContentUpdated(noteId: noteId, change: change));

    ctx.logger.debug('note $noteId content updated');
  }
}
