// database implementation of the state of the application

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

  Future<void> init() async {
    await _migrations.migrate(db);
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
      jsonEncode(tag.value),
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
