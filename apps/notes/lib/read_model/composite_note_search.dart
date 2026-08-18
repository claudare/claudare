import 'package:notes/read_model/note/resolved_note.dart';
import 'package:notes/read_model/note/resolved_note_read_model.dart';
import 'package:notes/read_model/search/search_read_model.dart';

// Quick and dirty way to query multiple databases at the same time
// This is done to simplify the search display functionality.
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
