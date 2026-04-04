import 'package:isolate_sqlite/isolate_sqlite.dart';

final noteMigrations = SqliteMigrations(migrationTable: 'migrations_note')..add(
  SqliteMigration(1, (db) async {
    print('applying note table read model migrations');
    // timestamps are strings
    await db.exec('''CREATE TABLE note (
      id STRING PRIMARY KEY,
      title TEXT,
      content TEXT,
      created_at TEXT,
      updated_at TEXT,
      is_deleted INTEGER,
      _local_sequence INTEGER
    )''');
    await db.exec(
      'CREATE INDEX idx_note_id_is_deleted ON note(id, is_deleted);',
    );
    await db.exec(
      'CREATE INDEX idx_note_local_sequence ON note(_local_sequence);',
    );

    // await db.exec('''CREATE TABLE tag (
    //   id STRING PRIMARY KEY,
    //   name TEXT,
    //   _localSequence INTEGER
    // )''');

    // // a way to link tags to notes.
    // // no need for foreign keys, just trying it for now
    // await db.exec('''CREATE TABLE note_tag (
    //   tag_id STRING,
    //   note_id STRING,
    //   PRIMARY KEY (tag_id, note_id),
    //   FOREIGN KEY (tag_id) REFERENCES tag(id),
    //   FOREIGN KEY (note_id) REFERENCES note(id)
    //   );
    // ''');

    // // experimenting. Probably will cause more issues that it will solve
    // await db.exec('PRAGMA foreign keys = ON;');
  }),
);
