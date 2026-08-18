import 'package:cqrs/cqrs.dart';
import 'package:crdt/crdt.dart';
import 'package:notes/event/note.dart';
import 'package:notes/read_model/note/note_data.dart';
import 'package:notes/read_model/note/note_projection_repo.dart';
import 'package:notes/stream_route/note_stream_route.dart';

class NoteProjection implements Projection<NoteEvent, String> {
  final NoteProjectionRepo _repo;

  const NoteProjection(this._repo);

  @override
  String get name => 'notes';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => noteStreamRoute;

  @override
  // temporary, this is being reworked
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() => _repo.reset();

  @override
  void onBatchApplied() {}

  @override
  Future<void> apply(String noteId, NoteEvent event, EventMetadata metadata) {
    switch (event) {
      case NoteContentUpdated(:final newContent):
        return _repo.getAndStore(
          noteId,
          (note) =>
              note.copyWith(content: newContent, updatedAt: metadata.occuredAt),
        );
      case NoteCreated():
        return _repo.store(
          NoteData(
            noteId: noteId,
            title: CrdtValueLatestWriteWins<String>('', metadata.occuredAt),
            content: '',
            createdAt: metadata.occuredAt,
            updatedAt: metadata.occuredAt,
            trashedAt: null,
          ),
        );
      case NoteRestored():
        return _repo.getAndStore(
          noteId,
          (note) => note.copyWithTrashedValue(trashedAt: null),
        );
      case NoteTitleUpdated(:final newTitle):
        return _repo.getAndStore(
          noteId,
          (note) => note.copyWith(
            titlePair: CrdtValueDateTimePair(newTitle, metadata.occuredAt),
            updatedAt: metadata.occuredAt,
          ),
        );
      case NoteTrashed():
        return _repo.getAndStore(
          noteId,
          (note) => note.copyWithTrashedValue(trashedAt: metadata.occuredAt),
        );
    }
  }
}
