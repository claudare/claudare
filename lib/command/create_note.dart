import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/note/_note_codec.dart';
import 'package:notes_app_v0/event/note/note.dart';
import 'package:notes_app_v0/stream_id/note_stream_id.dart';

class CreateNoteInput implements CommandInput {
  final String noteId;
  final String initialContent;
  final String initialTitle;

  const CreateNoteInput({
    required this.noteId,
    required this.initialContent,
    required this.initialTitle,
  });

  @override
  String get kind => 'createNote';

  @override
  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'initialContent': initialContent,
      'initialTitle': initialTitle,
    };
  }
}

class CreateNote implements Command<CreateNoteInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    await stream.mustNotExist();

    stream.append(NoteCreated());
  }
}
