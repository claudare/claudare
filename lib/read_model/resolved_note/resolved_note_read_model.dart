import 'package:notes_app_v0/model/resolved_note.dart';

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
}
