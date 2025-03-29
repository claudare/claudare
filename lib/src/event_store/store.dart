import 'dart:typed_data';

import 'package:core/src/database.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/any_event.dart';
import 'package:core/src/event_store/event_clock.dart';
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

class EventStore extends Database {
  EventStore(super.path);
  EventStore.temporary() : super.temporary();

  late EventClock _vectorClock;

  Future<void> initialize() async {
    await _migrations.migrate(db);

    _vectorClock = await _loadVectorClock();
  }

  EventClock get vectorClock => _vectorClock;

  /// returns an iterator of events from the given event clock
  /// TODO: implement batching on sqlite side
  /// this has a race condition where new events come from another device
  /// while these ones are being replicated
  /// this also needs "toEventClock"
  Stream<StoredEvent> getEvents(EventClock fromEventClock) async* {
    // query for the event clock

    final args = List<int>.filled(fromEventClock.length * 2, 0);
    final whereClause = List<String>.filled(
      fromEventClock.length,
      '(device_id = ? AND timestamp > ?)',
    ).join(' OR ');

    for (var i = 0; i < fromEventClock.length; i++) {
      final entry = fromEventClock.entries.elementAt(i);
      final deviceId = entry.key.value;
      final timestamp = entry.value.value;
      args[2 * i] = deviceId;
      args[2 * i + 1] = timestamp;
    }

    final rows = await db.execute('''
      SELECT device_id, timestamp, data
      FROM event
      WHERE $whereClause
      ORDER BY timestamp ASC;
    ''', args);

    for (final row in rows) {
      final timestamp = Timestamp(row['timestamp']);
      final deviceId = DeviceId(row['device_id']);
      final eventId = EventId(timestamp, deviceId);

      final data = row['data'] as Uint8List;

      yield StoredEvent(eventId, data);
    }
  }

  Future<void> storeEvent(StoredEvent envelope) async {
    _vectorClock.update(envelope.id);

    final data = envelope.data;
    await db.execute(
      '''
      INSERT INTO event (device_id, timestamp, data)
      VALUES (?, ?, ?);
    ''',
      [envelope.id.deviceId.value, envelope.id.timestamp.value, data],
    );
  }

  Future<EventClock> _loadVectorClock() async {
    final rows = await db.execute('''
      SELECT device_id, MAX(timestamp) as timestamp
      FROM event
      GROUP BY device_id;
    ''');
    final deviceTimestamp = <DeviceId, Timestamp>{};
    for (final row in rows) {
      deviceTimestamp[DeviceId(row['device_id'])] = Timestamp(row['timestamp']);
    }
    return EventClock(deviceTimestamp);
  }
}
