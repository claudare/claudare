import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/model/resolved_note.dart';
import 'package:notes_app_v0/read_model/resolved_note/resolved_note_read_model.dart';

class ResolvedNoteReadModelSqlite implements ResolvedNoteReadModel {
  final IsolateSqlite _db;

  const ResolvedNoteReadModelSqlite(this._db);

  String _orderWhereSql(ResolvedNoteQueryOrder order) {
    switch (order) {
      case ResolvedNoteQueryOrder.createdAtDescending:
        return 'ORDER BY created_at DESC';
      case ResolvedNoteQueryOrder.createdAtAscending:
        return 'ORDER BY created_at ASC';
      case ResolvedNoteQueryOrder.updatedAtDescending:
        return 'ORDER BY updated_at DESC';
      case ResolvedNoteQueryOrder.updatedAtAscending:
        return 'ORDER BY updated_at ASC';
    }
  }

  String _categoryWhereSql(ResolvedNoteQueryCategory category) {
    switch (category) {
      case ResolvedNoteQueryCategory.available:
        return 'WHERE trashed_at IS NOT NULL';
      case ResolvedNoteQueryCategory.trashed:
        return 'WHERE trashed_at IS NOT NULL';
      case ResolvedNoteQueryCategory.favorited:
        return 'WHERE 1 = 2'; // Not implemented yet
    }
  }

  @override
  Future<List<ResolvedNote>> query(
    ResolvedNoteQueryCategory category,
    ResolvedNoteQueryOrder order,
  ) async {
    final whereClause = _categoryWhereSql(category);
    final orderClause = _orderWhereSql(order);

    final rows = await _db.query(
      'SELECT id, title, content, created_at, updated_at, trashed_at FROM note $whereClause $orderClause;',
    );

    return rows
        .map(
          (row) => ResolvedNote(
            noteId: row[0] as String,
            title: row[1] as String,
            content: row[2] as String,
            createdAt: DateTime.parse(row[3] as String),
            updatedAt: DateTime.parse(row[4] as String),
            trashedAt: row[5] == null ? null : DateTime.parse(row[5] as String),
          ),
        )
        .toList();
  }
}
