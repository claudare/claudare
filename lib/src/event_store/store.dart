import 'dart:typed_data';

import 'package:core/src/database.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/timestamp.dart';
import 'package:sqlite_async/sqlite_async.dart';

final _migrations = SqliteMigrations(migrationTable: 'migrations_event_store')
  ..add(
    SqliteMigration(1, (tx) async {
      // composite primary key as this is how data is queried
      await tx.execute('''
      CREATE TABLE event (
        timestamp INT NOT NULL,
        sequence INT NOT NULL,
        device_id INT NOT NULL,
        data BLOB NOT NULL,
        PRIMARY KEY (timestamp, sequence, device_id)
      );
    ''');
      // await tx.execute('''
      //   CREATE INDEX idx_event_timestamp ON event(timestamp);
      // ''');
    }),
  );

class EventStore extends DatabaseBase {
  EventStore(super.path);
  EventStore.temporary() : super.temporary();

  late EventVectorClock _vectorClock;

  @override
  Future<void> init() async {
    await super.init();

    await _migrations.migrate(db);

    _vectorClock = await _loadVectorClock();
  }

  EventVectorClock get vectorClock => _vectorClock;

  /// returns an iterator of events from the given event clock
  /// TODO: should this be a stream, or just a list?
  Stream<StoredEvent> getEvents(EventVectorClock cursor, int limit) async* {
    // ohhh, cant have an empty one
    if (cursor.length == 0) {
      throw Exception('Cannot query events by an empty cursor');
    }

    final args = List<int>.empty(growable: true);
    final whereClause = List<String>.filled(
      cursor.length,
      '(device_id = ? AND timestamp > ? AND sequence > ?)',
    ).join(' OR ');

    // iterate
    for (final eventId in cursor.entries) {
      final deviceId = eventId.deviceId.value;
      final timestamp = eventId.timestamp.value;
      final sequence = eventId.sequence;
      args.addAll([deviceId, timestamp, sequence]);
    }
    args.add(limit);

    final sql = '''
      SELECT timestamp, sequence, device_id, data
      FROM event
      WHERE $whereClause
      ORDER BY timestamp ASC, sequence ASC, device_id ASC
      LIMIT ?;
    ''';
    final rows = await db.execute(sql, args);

    for (final row in rows) {
      final timestamp = Timestamp(row['timestamp']);
      final sequence = row['sequence'] as int;
      final deviceId = DeviceId(row['device_id']);
      final eventId = EventId(timestamp, sequence, deviceId);

      final data = row['data'] as Uint8List;

      yield StoredEvent(eventId, data);
    }
  }

  Future<void> storeEvent(StoredEvent envelope) async {
    // vector clock update ensures that we are not storing events in the past
    // of the vector clock. This is really important to allow getEvents to work
    _vectorClock.update(envelope.id);

    final id = envelope.id;
    final data = envelope.bytes;
    await db.execute(
      '''
      INSERT INTO event (device_id, timestamp, sequence, data)
      VALUES (?, ?, ?, ?);
    ''',
      [id.deviceId.value, id.timestamp.value, id.sequence, data],
    );
  }

  Future<int> eventCount() async {
    return await db
        .get('SELECT COUNT(*) FROM event')
        .then((row) => row['COUNT(*)'] as int);
  }

  Future<EventVectorClock> _loadVectorClock() async {
    final rows = await db.execute('''
      SELECT device_id, MAX(timestamp) as timestamp, MAX(sequence) as sequence
      FROM event
      GROUP BY device_id;
    ''');
    final eventIds = List<EventId>.from(
      rows.map(
        (row) => EventId(
          Timestamp(row['timestamp']),
          int.parse(row['sequence']),
          DeviceId(row['device_id']),
        ),
      ),
    );

    return EventVectorClock.fromEventIds(eventIds);
  }
}
