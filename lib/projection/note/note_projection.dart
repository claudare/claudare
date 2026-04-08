import 'package:core/cqrs.dart';
import 'package:core/crdt.dart';
import 'package:notes_app_v0/event/note/_note_codec.dart';
import 'package:notes_app_v0/event/note/note.dart';
import 'package:notes_app_v0/model/note_data.dart';
import 'package:notes_app_v0/repo/note/note_internal_repo.dart';
import 'package:notes_app_v0/stream_id/note_stream_id.dart';

/// Single projection that holds both the summary (string title and content)
/// and the granular CRDT changes. 2 separate read models are used to query it.
class NoteProjection implements Projection<NoteEvent, String> {
  final NoteInternalRepo _repo;

  NoteProjection(this._repo);

  @override
  String get name => 'note.complete';

  @override
  EventCodec<NoteEvent> get eventCodec => noteCodec;

  @override
  StreamIdPattern<String> get streamIdPattern => noteStreamId;

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
      case NoteDeleted():
        return _repo.getAndStore(
          noteId,
          metadata.localSequence,
          (note) => note.copyWithTrashedValue(trashedAt: metadata.occuredAt),
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
    }
  }
}
