import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_administration.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';
import 'package:cqrs/src/cqrs/event_store/sqlite/event_db.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

class SqliteEventStore implements EventStore {
  final EventDb _eventDb;
  final IsolateSqlite _iso;
  final int _eventFetchPageSize;

  SqliteEventStore(IsolateSqlite iso, {int eventFetchPageSize = 50})
    : _eventDb = EventDb(iso),
      _iso = iso,
      _eventFetchPageSize = eventFetchPageSize;

  Future<void> migrate() async {
    await _eventDb.migrate();
  }

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String streamId,
    int versionCursor,
  ) {
    return _eventDb.getStreamEvents(
      streamId,
      _eventFetchPageSize,
      versionCursor,
    );
  }

  @override
  Future<GetStreamInfoResult?> getStreamInfo(String streamId) {
    return _eventDb.getStreamInfo(streamId);
  }

  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) {
    return _eventDb.saveChanges(command, appends);
  }

  @override
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int sequenceNumber,
  ) {
    return _eventDb.getLocalEvents(
      patternFilter,
      sequenceNumber,
      _eventFetchPageSize,
    );
  }

  @override
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) {
    return _eventDb.getLocalLastEvent(patternFilter);
  }

  @override
  Future<GetStatisticsResult> getStatistics() async {
    final count = await _iso.queryValue<int>('SELECT COUNT(*) FROM event');
    // not accurate, but okay for now
    final storageSize = await _iso.queryValue<int>(
      'SELECT COALESCE(SUM(LENGTH(detail)), 0) FROM event',
    );

    return GetStatisticsResult(eventCount: count, storageSize: storageSize);
  }

  @override
  Future<void> reset() async {
    await _iso.transaction((tx) {
      tx.execute('DELETE FROM command_record');
      tx.execute('DELETE FROM event');
      tx.execute('DELETE FROM stream');
    });
  }
}
