import 'package:core/cqrs.dart';
import 'package:core/utils.dart';
import 'package:notes/event/note/_note_codec.dart';
import 'package:notes/event/note/note.dart';
import 'package:notes/stream_id/note_stream_id.dart';

class CreateNoteInput implements CommandInput {
  final String noteId;

  const CreateNoteInput({required this.noteId});

  @override
  String get kind => 'createNote';

  @override
  encode() {
    return JsonConverter.encode({'noteId': noteId});
  }

  @override
  String toString() {
    return 'CreateNoteInput{noteId: $noteId}';
  }
}

class CreateNote implements Command<CreateNoteInput> {
  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream(noteCodec, noteStreamId, noteId);

    await stream.mustNotExist();

    stream.append(NoteCreated());

    print('note $noteId created');
  }
}
