import 'package:cqrs/cqrs.dart';
import 'package:notes_app/src/application/paths.dart';
import 'package:notes_app/src/event/note.dart';

class UpdateNoteTitle implements Command {
  final String noteId;
  final String fullValue;

  const UpdateNoteTitle({required this.noteId, required this.fullValue});

  @override
  String toString() {
    return 'UpdateNoteTitle{noteId: $noteId, fullValue: $fullValue}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStream(noteId));

    await stream.mustExist();

    stream.append(NoteTitleUpdated(noteId: noteId, newTitle: fullValue));

    ctx.logger.debug('note $noteId title updated');
  }
}
