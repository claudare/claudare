import 'package:cqrs/cqrs.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:notes/event/note/note.dart';
import 'package:notes/projection/search/search_projection_repo.dart';
import 'package:notes/stream_route/note_stream_route.dart';

// what if more then one event type is needed?
class SearchProjection implements Projection<NoteEvent, String> {
  final SearchProjectionRepo _repo;
  final StandardProjectionFailureHandler _failureHandler;
  final Logger _logger;

  const SearchProjection(this._repo, this._failureHandler, this._logger);

  @override
  // TODO: for now search database is never cleared, as permanent delition is not implemented
  Future<void> apply(String noteId, NoteEvent event, EventMetadata metadata) {
    _logger.debug('applying search projection $noteId');
    switch (event) {
      case NoteContentUpdated(:final newContent):
        return _repo.upsertContent(
          UpsertInput(
            noteId: noteId,
            value: newContent,
            timestamp: metadata.occuredAt,
          ),
        );
      case NoteTitleUpdated(:final newTitle):
        return _repo.upsertTitle(
          UpsertInput(
            noteId: noteId,
            value: newTitle,
            timestamp: metadata.occuredAt,
          ),
        );

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
  String get name => 'search';

  @override
  StreamRoute<String> get streamRoute => noteStreamRoute;

  @override
  ProjectionFailureHandler get failureHandler => _failureHandler;
}
