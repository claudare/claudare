import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/event_store/sqlite/event_db.dart';
import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

class SqliteEventStore implements EventStore {
  final EventDb _eventDb;

  SqliteEventStore(IsolateSqlite iso) : _eventDb = EventDb(iso);

  Future<void> migrate() async {
    await _eventDb.migrate();
  }

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String applicationId,
    String streamId,
    int count,
    int versionCursor,
  ) {
    return _eventDb.getStreamEvents(
      applicationId,
      streamId,
      count,
      versionCursor,
    );
  }

  @override
  Future<GetStreamInfoResult?> getStreamInfo(
    String applicationId,
    String streamId,
  ) {
    return _eventDb.getStreamInfo(applicationId, streamId);
  }

  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) {
    return _eventDb.saveChanges(command, appends);
  }

  @override
  Future<GetGlobalEventsResult> getGlobalEvents(
    String applicationId,
    int sequenceNumber,
    PatternFilter patternFilter,
    int count,
  ) {
    return _eventDb.getGlobalEvents(
      applicationId,
      sequenceNumber,
      patternFilter,
      count,
    );
  }
}
