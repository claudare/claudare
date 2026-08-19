import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

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
  const CreateNote();

  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    await stream.mustNotExist();

    stream.append(NoteCreated());

    ctx.logger.debug('note $noteId created');
  }
}
