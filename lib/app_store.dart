// database implementation of the application

import 'dart:convert';

import 'package:core/core.dart';
import 'package:core/database.dart';
import 'package:notes_app_v0/repo.dart';
import 'package:sqlite_async/sqlite_async.dart';

final _migrations = SqliteMigrations(migrationTable: 'migrations_app_store')
  ..add(
    SqliteMigration(1, (tx) async {
      await tx.execute('''
        CREATE TABLE note (
          id VARCHAR(24) PRIMARY KEY NOT NULL,
          data BLOB NOT NULL
        );
      ''');

      // full text search with sqlite
      // https://www.sqlite.org/fts5.html#the_trigram_tokenizer
      // issue is short search terms. As per docs:
      // Substrings consisting of fewer than 3 unicode characters do not match
      // any rows when used with a full-text query. If a LIKE or GLOB pattern
      // does not contain at least one sequence of non-wildcard unicode
      // characters, FTS5 falls back to a linear scan of the entire table.
      await tx.execute('''
        CREATE VIRTUAL TABLE note_fts
        USING fts5(id UNINDEXED, title, content, tags, tokenize="trigram");
      ''');

      // yep, noSQL life
      await tx.execute('''
        CREATE TABLE tag (
          name TEXT PRIMARY KEY NOT NULL,
          data BLOB NOT NULL
        );
      ''');

      await tx.execute('''
        CREATE TABLE note_order (
          value BLOB NOT NULL
        );
      ''');
    }),
  );

class AppStore extends DatabaseBase {
  AppStore(super.path);
  AppStore.temporary() : super.temporary();

  @override
  Future<void> init() async {
    await super.init();

    await _migrations.migrate(db);

    // insert empty order if none exists
    await db.execute('INSERT OR IGNORE INTO note_order (value) VALUES (?);', [
      json.encode(NoteOrderData([]).toJson()),
    ]);

    // optimize full text search
    await db.execute("INSERT INTO note_fts(note_fts) VALUES('optimize');");
  }

  Future<NoteData?> noteGet(GenericId id) async {
    final noteRes = await db.getOptional(
      'SELECT data FROM note WHERE id = ? LIMIT 1;',
      [id.toString()],
    );

    if (noteRes == null) {
      return null;
    }

    final note = NoteData.fromJson(json.decode(noteRes['data']));

    return note;
  }

  Future<void> noteSave(NoteData note) async {
    await db.execute('INSERT OR REPLACE INTO note (id, data) VALUES (?, ?);', [
      note.id.toString(),
      json.encode(note.toJson()),
    ]);
  }

  Future<void> noteDelete(GenericId id) async {
    final res = await db.execute(
      'DELETE FROM note WHERE id = ? RETURNING id;',
      [id.toString()],
    );
    if (res.isEmpty) {
      // TODO: proper logging
      print('NOTE NOTE FOUND: ${id.toString()}!!!');
      // throw ItemNotFoundException(id.toString());
    }
  }

  Future<void> noteSearchInit(GenericId id) async {
    await db.execute(
      'INSERT INTO note_fts (id, title, content) VALUES (?, ?, ?);',
      [id.toString(), '', ''],
    );
  }

  Future<void> noteSearchUpdate(
    GenericId id, {
    String? title,
    String? content,
    String? tags,
  }) async {
    if (title != null) {
      await db.execute('UPDATE note_fts SET title = ? WHERE id = ?;', [
        title,
        id.toString(),
      ]);
    }
    if (content != null) {
      await db.execute('UPDATE note_fts SET content = ? WHERE id = ?;', [
        content,
        id.toString(),
      ]);
    }
    if (tags != null) {
      await db.execute('UPDATE note_fts SET tags = ? WHERE id = ?;', [
        tags,
        id.toString(),
      ]);
    }
  }

  Future<void> noteSearchDelete(GenericId id) async {
    await db.execute('DELETE FROM note_fts WHERE id = ?;', [id.toString()]);
  }

  Future<List<GenericId>> noteSearchQuery(String query) async {
    // final rows = await db.getAll('SELECT * FROM note_fts(?);', [query]);
    final likeQuery = '%$query%';
    final rows = await db.getAll(
      'SELECT id FROM note_fts WHERE title LIKE ? OR content LIKE ? OR tags LIKE ?;',
      [likeQuery, likeQuery, likeQuery],
    );

    // print('search rows $rows');

    if (rows.isEmpty) {
      return [];
    }
    return rows.map((row) => GenericId.fromString(row['id'])).toList();
  }

  /// gets the complete list of tags
  /// this function is a bit too heavy on logic for my liking
  /// need to figure out how to deal with complex data structures serialized
  Future<TagsData> tagsGet() async {
    final rows = await db.getAll('SELECT name, data FROM tag;');
    final tags =
        rows
            .map(
              (row) =>
                  TagData.fromJsonValue(row['name'], json.decode(row['data'])),
            )
            .toList();

    return TagsData.fromTagDataList(tags);
  }

  Future<void> tagSave(TagData tag) async {
    await db.execute('INSERT OR REPLACE INTO tag (name, data) VALUES (?, ?);', [
      tag.name,
      jsonEncode(tag.toJsonValue()),
    ]);
  }

  Future<void> tagDelete(String name) async {
    final row = await db.execute(
      'DELETE FROM tag WHERE name = ? RETURNING name;',
      [name],
    );
    if (row.isEmpty) {
      print('TAG NOT FOUND: $name!!!');
      // throw ItemNotFoundException('tag with name "$tagName"');
    }
  }

  Future<NoteOrderData> noteOrderGet() async {
    final row = await db.get('SELECT value FROM note_order LIMIT 1;');
    return NoteOrderData.fromJson(jsonDecode(row['value']));
  }

  Future<void> noteOrderSave(NoteOrderData ordering) async {
    await db.execute('UPDATE note_order SET value = ?;', [
      jsonEncode(ordering.toJson()),
    ]);
  }
}
