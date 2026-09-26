import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

/// Appends text as another CRDT writer for development and tests.
class TestSimulateExternalNoteContentAppend implements Command {
  final String noteId;
  final String text;
  final String actorId;

  const TestSimulateExternalNoteContentAppend({
    required this.noteId,
    required this.text,
    required this.actorId,
  });

  @override
  Future<void> handle(ctx) async {
    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));
    final document = CrdtText();
    var exists = false;
    await for (final event in stream.scan()) {
      if (event is NoteCreated) exists = true;
      if (event is NoteContentUpdated) document.applyChange(event.change);
    }
    if (!exists) throw const CommandException('note does not exist');
    final editor = CrdtTextEditContext(document: document, actorId: actorId);
    editor.insert(document.length, text);
    final change = editor.prepareChange();
    if (change != null) {
      stream.append(NoteContentUpdated(noteId: noteId, change: change));
    }
  }
}
