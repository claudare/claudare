import 'package:cqrs/cqrs.dart';
import 'package:notes/event/note.dart';
import 'package:notes/application/paths.dart';

class CreateNote implements Command {
  final String noteId;

  const CreateNote({required this.noteId});

  @override
  String toString() {
    return 'CreateNote{noteId: $noteId}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStream(noteId));

    await stream.mustNotExist();

    stream.append(NoteCreated(noteId: noteId));

    ctx.logger.debug('note $noteId created');
  }
}
