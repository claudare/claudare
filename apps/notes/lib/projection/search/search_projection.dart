import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:notes/event/note/note.dart';
import 'package:notes/projection/search/search_projection_repo.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class SearchProjection implements Projection<NoteEvent, String> {
  final SearchProjectionRepo _repo;
  final StandardProjectionFailureHandler _failureHandler;
  final Logger _logger;

  const SearchProjection(this._repo, this._failureHandler, this._logger);

  @override
  String get name => 'search';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => noteStreamRoute;

  @override
  ProjectionFailureHandler get failureHandler => _failureHandler;

  @override
  Future<void> reset() => _repo.reset();

  @override
  void onBatchApplied() {}

  @override
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
        return Future.value();
    }
  }
}
