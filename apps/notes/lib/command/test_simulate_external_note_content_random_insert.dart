import 'dart:math';

import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt_text.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

/// Inserts text at a random Unicode scalar boundary for visual testing.
class TestSimulateExternalNoteContentRandomInsert implements Command {
  final String noteId;
  final String text;
  final String actorId;
  final Random random;

  const TestSimulateExternalNoteContentRandomInsert({
    required this.noteId,
    required this.text,
    required this.actorId,
    required this.random,
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
    final boundaries = [0];
    for (final rune in document.text.runes) {
      boundaries.add(boundaries.last + (rune > 0xffff ? 2 : 1));
    }
    final editor = CrdtTextEditContext(document: document, actorId: actorId);
    editor.insert(boundaries[random.nextInt(boundaries.length)], text);
    final change = editor.prepareChange();
    if (change != null) {
      stream.append(NoteContentUpdated(noteId: noteId, change: change));
    }
  }
}
