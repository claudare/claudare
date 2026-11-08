import 'package:cqrs/cqrs.dart';
import 'package:fts/fts.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes_app/src/application/paths.dart';
import 'package:notes_app/src/event/note.dart';

class SearchProjection implements Projection<NoteEvent> {
  @override
  String get name => 'notes-search';

  @override
  LogFilter get filter => allNotesFilter;

  final Fts _fts;
  final Map<String, NoteState> notes = {};

  SearchProjection(this._fts);

  @override
  Future<int> load() async {
    // nothing is serialized, fresh start every time
    return -1;
  }

  @override
  Future<void> apply(envelope) async {
    final noteId = noteIdFromStream(envelope.streamPath);

    final note = notes.putIfAbsent(noteId, () => NoteState(noteId));
    note.apply(envelope);

    await _fts.upsert(noteId, note.content, envelope.logPosition);
  }

  @override
  Future<void> onStreamDeleted(deletion) async {
    final noteId = noteIdFromStream(deletion.streamPath);
    notes.remove(noteId);
    await _fts.delete(noteId, deletion.logPosition);
  }

  Future<List<String>> search(String text, {required int resultCount}) async {
    return _fts.query(text, resultCount);
  }
}
