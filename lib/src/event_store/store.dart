import 'package:core/src/database.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/timestamp.dart';
import 'package:sqlite_async/sqlite_async.dart';

final _migrations = SqliteMigrations(
  migrationTable: 'migrations_event_store',
)..add(
  SqliteMigration(1, (tx) async {
    // table event should have a composite primary key of device_id and timestamp
    await tx.execute('''
      CREATE TABLE event (
        device_id INT NOT NULL,
        timestamp INT NOT NULL,
        data BLOB NOT NULL,
        PRIMARY KEY (device_id, timestamp)
      );
    ''');
    await tx.execute('''
      CREATE INDEX idx_event_timestamp ON event(timestamp);
    ''');
  }),
);

class EventStore extends DatabaseBase {
  EventStore(super.path);
  EventStore.temporary() : super.temporary();

  late EventVectorClock _vectorClock;

  Future<void> init() async {
    await _migrations.migrate(db);

    _vectorClock = await _loadVectorClock();
  }

  EventVectorClock get vectorClock => _vectorClock;

  /// returns an iterator of events from the given event clock
  /// TODO: should this be a stream, or just a list?
  Stream<StoredEvent> getEvents(
    EventVectorClockRange cursor,
    int limit,
  ) async* {
    if (cursor.isEmpty) {
      throw Exception('cursor should never be empty.');
    }

    final args = List<int>.empty(growable: true);
    // final args = List<int>.filled(cursor.length * 2, 0);
    final whereClause = List<String>.filled(
      cursor.length,
      '(device_id = ? AND timestamp > ? AND timestamp <= ?)',
    ).join(' OR ');

    // iterate
    for (final entry in cursor.ranges.entries) {
      final deviceId = entry.key.value;
      final timestampStart = entry.value.start.value;
      final timestampEnd = entry.value.end.value;
      args.addAll([deviceId, timestampStart, timestampEnd]);
    }

    args.add(limit);

    final rows = await db.execute('''
      SELECT device_id, timestamp, data
      FROM event
      WHERE $whereClause
      ORDER BY timestamp ASC, device_id ASC
      LIMIT ?;
    ''', args);

    for (final row in rows) {
      final timestamp = Timestamp(row['timestamp']);
      final deviceId = DeviceId(row['device_id']);
      final eventId = EventId(timestamp, deviceId);

      final data = row['data'] as String;

      yield StoredEvent(eventId, data);
    }
  }

  Future<void> storeEvent(StoredEvent envelope) async {
    // vector clock update ensures that we are not storing events in the past
    // of the vector clock. This is really important to allow getEvents to work
    _vectorClock.update(envelope.id);

    final id = envelope.id;
    final data = envelope.data;
    await db.execute(
      '''
      INSERT INTO event (device_id, timestamp, data)
      VALUES (?, ?, ?);
    ''',
      [id.deviceId.value, id.timestamp.value, data],
    );
  }

  Future<EventVectorClock> _loadVectorClock() async {
    final rows = await db.execute('''
      SELECT device_id, MAX(timestamp) as timestamp
      FROM event
      GROUP BY device_id;
    ''');
    final eventIds = List<EventId>.from(
      rows.map(
        (row) =>
            EventId(Timestamp(row['timestamp']), DeviceId(row['device_id'])),
      ),
    );

    return EventVectorClock.fromEventIds(eventIds);
  }
}
