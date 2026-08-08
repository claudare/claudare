import 'package:core/cqrs.dart';
import 'package:core/crdt.dart';
import 'package:notes/event/note/_note_codec.dart';
import 'package:notes/event/note/note.dart';
import 'package:notes/model/note_data.dart';
import 'package:notes/stream_id/note_stream_id.dart';

import 'note_projection_repo.dart';

/// Single projection that holds both the summary (string title and content)
/// and the granular CRDT changes. 2 separate read models are used to query it.
class NoteProjection implements Projection<NoteEvent, String> {
  final NoteProjectionRepo _repo;
  final StandardProjectionFailureHandler _failureHandler;

  const NoteProjection(this._repo, this._failureHandler);

  @override
  String get name => 'note.complete';

  @override
  EventCodec<NoteEvent> get eventCodec => noteCodec;

  @override
  StreamIdPattern<String> get streamIdPattern => noteStreamId;

  @override
  ProjectionFailureHandler get failureHandler => _failureHandler;

  @override
  Future<void> reset() async {
    await _repo.reset();
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() {
    return _repo.checkpoint();
  }

  @override
  Future<void> apply(String noteId, NoteEvent event, EventMetadata metadata) {
    switch (event) {
      case NoteContentUpdated(:final newContent):
        return _repo.getAndStore(
          noteId,
          metadata.localSequence,
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
          metadata.localSequence,
        );
      case NoteRestored():
        return _repo.getAndStore(
          noteId,
          metadata.localSequence,
          (note) => note.copyWithTrashedValue(trashedAt: null),
        );
      case NoteTitleUpdated(:final newTitle):
        return _repo.getAndStore(
          noteId,
          metadata.localSequence,
          (note) => note.copyWith(
            titlePair: CrdtValueDateTimePair(newTitle, metadata.occuredAt),
            updatedAt: metadata.occuredAt,
          ),
        );
      case NoteTrashed():
        return _repo.getAndStore(
          noteId,
          metadata.localSequence,
          (note) => note.copyWithTrashedValue(trashedAt: metadata.occuredAt),
        );
    }
  }
}
