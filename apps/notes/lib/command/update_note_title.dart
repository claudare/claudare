import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:notes/event/note/note.dart';
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
  final Logger _logger;

  const UpdateNoteTitle(this._logger);

  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    // This implementation is not concurrent, as concurrency will need to use
    // the actual device time.
    // TODO: make this work concurrently, as title will NOT be a CRDT.
    // ctx.currentTime() is available in the projection through metadata!

    await stream.mustExist();

    stream.append(NoteTitleUpdated(noteId: noteId, newTitle: input.fullValue));

    _logger.debug('note $noteId title updated');
  }
}
