import 'package:notes/model/resolved_note.dart';

enum ResolvedNoteQueryOrder {
  createdAtDescending,
  createdAtAscending,
  updatedAtDescending,
  updatedAtAscending,
}

enum ResolvedNoteQueryCategory { all, notTrashed, trashed, favorited }

abstract interface class ResolvedNoteReadModel {
  Future<List<ResolvedNote>> query(
    ResolvedNoteQueryCategory category,
    ResolvedNoteQueryOrder order,
  );

  Future<ResolvedNote?> getById(String noteId);

  /// Returns a list of [ResolvedNote]s for the given [noteIds].
  /// Result could have less then [noteIds] elements if some are not found.
  Future<List<ResolvedNote>> getManyById(List<String> noteIds);
}
