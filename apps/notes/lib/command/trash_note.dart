import 'package:cqrs/cqrs.dart';
import 'package:notes/application/paths.dart';
import 'package:notes/event/note.dart';

class TrashNote implements Command {
  final String noteId;

  const TrashNote({required this.noteId});

  @override
  String toString() {
    return 'TrashNote{noteId: $noteId}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStream(noteId));

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
      throw const CommandException('note does not exist');
    }
    if (trashed) {
      throw const CommandException('note already trashed');
    }

    stream.append(NoteTrashed(noteId: noteId));
  }
}
