import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/event/tag/tag.dart';
import 'package:notes/stream_route/tag_stream_route.dart';

class TagProjection extends SqliteProjection<TagEvent, String> {
  final StandardProjectionFailureHandler _failureHandler =
      StandardProjectionFailureHandler();

  @override
  String get name => 'tags';

  @override
  int get version => 1;

  @override
  ProjectionFailureHandler get failureHandler => _failureHandler;

  @override
  StreamRoute<String> get streamRoute => tagStreamRoute;

  @override
  Future<void> reset(IsolateSqlite db) async {
    await db.transaction((tx) {
      tx.execute('DROP TABLE IF EXISTS note_tag;');
      tx.execute('DROP TABLE IF EXISTS tag;');
      tx.execute('''CREATE TABLE tag (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )''');
      tx.execute('''CREATE TABLE note_tag (
        tag_id TEXT NOT NULL,
        note_id TEXT NOT NULL,
        PRIMARY KEY (tag_id, note_id)
      )''');
    });
  }

  @override
  void onBatchApplied() {}

  @override
  void apply(
    SyncContext tx,
    String tagId,
    TagEvent event,
    EventMetadata metadata,
  ) {
    switch (event) {
      case TagAssigned(:final noteId):
        tx.execute('INSERT INTO note_tag (note_id, tag_id) VALUES (?, ?)', [
          noteId,
          tagId,
        ]);
      case TagCreated(:final name):
        tx.execute('INSERT INTO tag (id, name) VALUES (?, ?)', [tagId, name]);
      case TagRemoved():
        // TODO: this will not work, need shadow delete, always
        tx.execute('DELETE FROM tag WHERE id = ?', [tagId]);
      case TagRenamed(:final newName):
        tx.execute('UPDATE tag SET name = ? WHERE id = ?', [newName, tagId]);
      case TagUnassigned(:final noteId):
        tx.execute('DELETE FROM note_tag WHERE note_id = ? AND tag_id = ?', [
          noteId,
          tagId,
        ]);
    }
  }
}
