import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class UpdateNoteTitleInput implements CommandInput {
  final String noteId;
  final String fullValue;

  const UpdateNoteTitleInput({required this.noteId, required this.fullValue});

  @override
  String get kind => 'updateNoteTitle';

  @override
  encode() {
    return JsonConverter.encode({'noteId': noteId, 'fullValue': fullValue});
  }

  @override
  String toString() {
    return 'UpdateNoteTitleInput{noteId: $noteId, fullValue: $fullValue}';
  }
}

class UpdateNoteTitle implements Command<UpdateNoteTitleInput> {
  const UpdateNoteTitle();

  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    await stream.mustExist();

    stream.append(NoteTitleUpdated(noteId: noteId, newTitle: input.fullValue));

    ctx.logger.debug('note $noteId title updated');
  }
}
