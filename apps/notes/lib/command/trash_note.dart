import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class TrashNoteInput implements CommandInput {
  final String noteId;

  const TrashNoteInput({required this.noteId});

  @override
  String get kind => 'deleteNote';

  @override
  encode() {
    return JsonConverter.encode({'noteId': noteId});
  }

  @override
  String toString() {
    return 'TrashNoteInput{noteId: $noteId}';
  }
}

class TrashNote implements Command<TrashNoteInput> {
  const TrashNote();

  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

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

    stream.append(NoteTrashed());
  }
}
