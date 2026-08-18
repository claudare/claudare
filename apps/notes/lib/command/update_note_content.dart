import 'package:cqrs/cqrs.dart';
import 'package:common/common.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:notes/event/note.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class UpdateNoteContentInput implements CommandInput {
  final String noteId;
  final String overrideContent;

  const UpdateNoteContentInput({
    required this.noteId,
    required this.overrideContent,
  });

  @override
  String get kind => 'updateNoteContent';

  @override
  encode() {
    return JsonConverter.encode({
      'noteId': noteId,
      'overrideContent': overrideContent,
    });
  }

  @override
  String toString() {
    return 'UpdateNoteContentInput{noteId: $noteId, overrideContent: $overrideContent}';
  }
}

class UpdateNoteContent implements Command<UpdateNoteContentInput> {
  final Logger _logger;

  const UpdateNoteContent(this._logger);

  @override
  Future<void> handle(input, ctx) async {
    final noteId = input.noteId;

    final stream = ctx.stream<NoteEvent>(noteStreamRoute.buildPath(noteId));

    // This implementation is not concurrent, as concurrency will need to use
    // the actual device time.
    // TODO: make this work concurrently, atleast for the title
    // ctx.currentTime() is available in the projection through metadata!
    // With proper merge crdt timestamps will not be needed

    await stream.mustExist();

    stream.append(
      NoteContentUpdated(noteId: noteId, newContent: input.overrideContent),
    );

    _logger.debug('note $noteId content updated');
  }
}
