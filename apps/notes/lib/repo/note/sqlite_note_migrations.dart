import 'package:isolate_sqlite/isolate_sqlite.dart';

final noteMigrations = SqliteMigrations(migrationTable: 'migrations_note')..add(
  SqliteMigration(1, (tx) {
    print('applying note table read model migrations');
    // timestamps are strings
    tx.execute('''CREATE TABLE note (
      id STRING PRIMARY KEY,
      title TEXT NOT NULL,
      title_updated_at TEXT,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      trashed_at TEXT,
      _local_sequence INTEGER NOT NULL
    )''');
    tx.execute('CREATE INDEX idx_note_id_trashed_at ON note(id, trashed_at);');
    tx.execute(
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
