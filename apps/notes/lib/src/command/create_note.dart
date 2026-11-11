import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:notes_app/src/event/note.dart';
import 'package:notes_app/src/application/paths.dart';

class CreateNote implements Command {
  final String noteId;
  final Logger logger;

  const CreateNote({required this.noteId, required this.logger});

  @override
  String toString() {
    return 'CreateNote{noteId: $noteId}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStream(noteId));

    await stream.mustNotExist();

    stream.append(NoteCreated());

    logger.debug('note $noteId created');
  }
}
