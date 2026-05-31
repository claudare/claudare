    // TODO with sqlite
    // optimize full text search
    // await db.exec("INSERT INTO note_fts(note_fts) VALUES('optimize');");

    // Future<void> noteSearchInit(GenericId id) async {
    //   await db.execute(
    //     'INSERT INTO note_fts (id, title, content) VALUES (?, ?, ?);',
    //     [id.toString(), '', ''],
    //   );
    // }

    // Future<void> noteSearchUpdate(
    //   GenericId id, {
    //   String? title,
    //   String? content,
    //   String? tags,
    // }) async {
    //   if (title != null) {
    //     await db.execute('UPDATE note_fts SET title = ? WHERE id = ?;', [
    //       title,
    //       id.toString(),
    //     ]);
    //   }
    //   if (content != null) {
    //     await db.execute('UPDATE note_fts SET content = ? WHERE id = ?;', [
    //       content,
    //       id.toString(),
    //     ]);
    //   }
    //   if (tags != null) {
    //     await db.execute('UPDATE note_fts SET tags = ? WHERE id = ?;', [
    //       tags,
    //       id.toString(),
    //     ]);
    //   }
    // }

    // Future<void> noteSearchDelete(GenericId id) async {
    //   await db.execute('DELETE FROM note_fts WHERE id = ?;', [id.toString()]);
    // }

    // Future<List<GenericId>> noteSearchQuery(String query) async {
    //   // final rows = await db.getAll('SELECT * FROM note_fts(?);', [query]);
    //   final likeQuery = '%$query%';
    //   final rows = await db.getAll(
    //     'SELECT id FROM note_fts WHERE title LIKE ? OR content LIKE ? OR tags LIKE ?;',
    //     [likeQuery, likeQuery, likeQuery],
    //   );

    //   // print('search rows $rows');

    //   if (rows.isEmpty) {
    //     return [];
    //   }
    //   return rows.map((row) => GenericId.fromString(row['id'])).toList();
    // }
