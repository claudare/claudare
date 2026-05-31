// quick and dirty combination of two different dbs
import 'package:notes_app_v0/model/resolved_note.dart';
import 'package:notes_app_v0/read_model/resolved_note/resolved_note_read_model.dart';
import 'package:notes_app_v0/read_model/search/search_read_model.dart';

/// TODO: this is temporary...
class CompositeNoteSearch {
  final ResolvedNoteReadModel _resolvedNoteReadModel;
  final SearchReadModel _searchReadModel;

  const CompositeNoteSearch(this._resolvedNoteReadModel, this._searchReadModel);

  Future<List<ResolvedNote>> queryComposite(
    String query,
    ResolvedNoteQueryCategory category,
    ResolvedNoteQueryOrder order,
  ) async {
    if (query.isEmpty) {
      return _resolvedNoteReadModel.query(category, order);
    }

    // first search
    final ids = await _searchReadModel.query(query);

    // then fetch full
    final notes = await _resolvedNoteReadModel.getManyById(ids);

    // then filter
    switch (category) {
      case ResolvedNoteQueryCategory.all:
        return notes;
      case ResolvedNoteQueryCategory.notTrashed:
        return notes.where((note) => !note.isTrashed).toList();
      case ResolvedNoteQueryCategory.trashed:
        return notes.where((note) => note.isTrashed).toList();
      case ResolvedNoteQueryCategory.favorited:
        return notes;
    }
  }
}
