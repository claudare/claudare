import 'package:core/src/database.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/timestamp.dart';
import 'package:sqlite_async/sqlite_async.dart';

final _migrations = SqliteMigrations(migrationTable: 'migrations_event_store')
  ..add(
    SqliteMigration(1, (tx) async {
      await tx.execute('''
        CREATE TABLE event (
          id VARCHAR(16) PRIMARY KEY NOT NULL,
          device INT NOT NULL,
          timestamp INT NOT NULL,
          data BLOB NOT NULL
        );
      ''');
      // TODO: index device + timestamp
    }),
  );

class EventStore extends Database {
  EventStore(super.path);
  EventStore.temporary() : super.temporary();

  Future<void> migrate() async {
    await _migrations.migrate(db);
  }
}

// simple event clock to get the "latest known value from each device"
class EventVectorClock {
  final Map<DeviceId, Timestamp> deviceTimestamp;

  const EventVectorClock(this.deviceTimestamp);

  void addEventId(EventId id) {
    // must check that older events are never inserted.
    // replication is strict from old to new
    final existing = deviceTimestamp[id.deviceId];

    if (existing != null && existing <= id.timestamp) {
      throw Exception(
        'New event is behind the latest known event. Latest ${id.timestamp.toISO8601()}, got ${existing.toISO8601()} instead.',
      );
    }

    deviceTimestamp[id.deviceId] = id.timestamp;
  }

  EventId operator [](DeviceId deviceId) {
    final ts = deviceTimestamp[deviceId];

    if (ts == null) {
      throw Exception('unknown device id $deviceId, not in VectorClock');
    }

    return EventId(ts, deviceId);
  }
}
