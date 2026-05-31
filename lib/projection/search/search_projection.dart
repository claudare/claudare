import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/note/_note_codec.dart';
import 'package:notes_app_v0/event/note/note.dart';
import 'package:notes_app_v0/projection/search/search_projection_repo.dart';
import 'package:notes_app_v0/stream_id/note_stream_id.dart';

// what if more then one event type is needed?
class SearchProjection implements Projection<NoteEvent, String> {
  final SearchProjectionRepo _repo;

  const SearchProjection(this._repo);

  @override
  // TODO: for now search database is never cleared, as permanent delition is not implemented
  Future<void> apply(String noteId, NoteEvent event, EventMetadata metadata) {
    switch (event) {
      case NoteContentUpdated(:final newContent):
        return _repo.upsertContent(noteId, newContent, metadata.localSequence);
      case NoteTitleUpdated(:final newTitle):
        return _repo.upsertTitle(noteId, newTitle, metadata.localSequence);

      default:
        // no-op
        return Future.value();
    }
  }

  @override
  Future<void> reset() {
    return _repo.reset();
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() {
    return _repo.checkpoint();
  }

  @override
  String get name => 'search';

  @override
  EventCodec<NoteEvent> get eventCodec => noteCodec;

  @override
  StreamIdPattern<String> get streamIdPattern => noteStreamId;
}
