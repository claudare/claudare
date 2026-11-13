import 'package:cqrs/cqrs.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/src/projection/note_projection.dart';
import 'package:notes_app/src/application/paths.dart';
import 'package:notes_app/src/event/note.dart';

/// Reconstructs note content and keeps its search index updated.
class SearchProjection implements Projection<SearchModel, NoteEvent> {
  @override
  String get name => 'notes-search';

  @override
  LogFilter get filter => allNotesFilter;

  final Fts _fts;

  SearchProjection(this._fts);

  @override
  ProjectionLoad<SearchModel> load() =>
      ProjectionLoad.initial(SearchModel._(_fts));

  @override
  Future<void> apply(
    SearchModel model,
    EventEnvelope<NoteEvent> envelope,
  ) async {
    final noteId = noteIdFromStream(envelope.streamPath);

    final note = model._notes.putIfAbsent(
      noteId,
      () => NoteProjection(noteId).load().model,
    );
    NoteProjection(noteId).apply(note, envelope);

    await model._fts.upsert(noteId, note.content, envelope.logPosition);
  }

  @override
  Future<void> onStreamDeleted(
    SearchModel model,
    StreamDeletion deletion,
  ) async {
    final noteId = noteIdFromStream(deletion.streamPath);
    model._notes.remove(noteId);
    await model._fts.delete(noteId, deletion.logPosition);
  }
}

/// Queries indexed note content in relevance order.
class SearchModel {
  final Fts _fts;
  final _notes = <String, NoteModel>{};

  SearchModel._(this._fts);

  /// Returns matching note identifiers, preserving backend ranking and limits.
  Future<List<String>> search(String text, {required int resultCount}) async {
    return _fts.query(text, resultCount);
  }
}
