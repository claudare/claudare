import 'package:core/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/event/tag/_tag_codec.dart';
import 'package:notes_app_v0/event/tag/tag.dart';
import 'package:notes_app_v0/stream_id/tag_stream_id.dart';

class TagProjection extends SqliteProjection<TagEvent, String> {
  @override
  String get name => 'tags';

  @override
  StreamIdPattern<String> get streamIdPattern => tagStreamId;

  @override
  EventCodec<TagEvent> get eventCodec => tagCodec;

  @override
  Future<void> reset(IsolateSqlite db) async {
    await db.transaction((tx) {
      tx.execute('DELETE FROM tag;');
      tx.execute('DELETE FROM note_tag;');
      tx.execute('DELETE FROM local_sequence;');
    });
  }

  @override
  Future<ProjectionCheckpoint> checkpoint(IsolateSqlite db) async {
    // TODO: check that transactions error like this
    try {
      final value = await db.queryValue<int>('SELECT value FROM checkpoint;');
      return ProjectionCheckpoint(value ?? 0);
    } catch (e) {
      print('checkpoint get error. Probably not initialized? $e');
      return ProjectionCheckpoint.notInitialized();
    }
  }

  @override
  void apply(
    Transaction tx,
    String tagId,
    TagEvent event,
    EventMetadata metadata,
  ) {
    tx.execute('UPDATE local_sequence SET value = ?;', [
      metadata.localSequence,
    ]);

    switch (event) {
      case TagAssigned(:final noteId):
        {
          tx.execute('INSERT INTO note_tag (note_id, tag_id) VALUES (?, ?)', [
            noteId,
            tagId,
          ]);
        }
      case TagCreated(:final name):
        {
          tx.execute('INSERT INTO tag (id, name) VALUES (?, ?)', [tagId, name]);
        }
      case TagRemoved():
        {
          // TODO: this will not work, need shadow delete, always
          tx.execute('DELETE FROM tag WHERE id = ?', [tagId]);
        }
      case TagRenamed(:final newName):
        {
          // TODO: this will not preserve the order
          // Utilize the CrtdValue here instead
          tx.execute('UPDATE tag SET name = ? WHERE id = ?', [newName, tagId]);
        }
      case TagUnassigned(:final noteId):
        {
          // but this is okay?
          tx.execute('DELETE FROM note_tag WHERE note_id = ? AND tag_id = ?', [
            noteId,
            tagId,
          ]);
        }
    }
  }
}
