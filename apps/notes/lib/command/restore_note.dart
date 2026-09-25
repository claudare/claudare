import 'package:cqrs/cqrs.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

/// Restores a trashed note.
class RestoreNote implements Command {
  final String noteId;

  const RestoreNote({required this.noteId});

  @override
  String toString() {
    return 'RestoreNote{noteId: $noteId}';
  }

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    final deletedCount = await stream.scan().fold(0, (count, ev) {
      if (ev is NoteTrashed) {
        return count + 1;
      } else if (ev is NoteRestored) {
        return count - 1;
      }
      return count;
    });

    if (deletedCount == 0) {
      throw Exception('note was not trashed');
    }
    if (deletedCount > 1) {
      // hhh, this should never happen, why do I check?
      // careful with throwing errors!
      throw StateError('note was trashed multiple times');
    }

    stream.append(NoteRestored(noteId: noteId));
  }
}
