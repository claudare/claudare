import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_bundle.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

final eventDatabaseMigrations = SqliteMigrations(
  migrationTable: 'migrations_event_database',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute('''CREATE TABLE command(
            log_position INTEGER PRIMARY KEY NOT NULL CHECK(log_position >= 0),
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            dependency BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            event_count INTEGER NOT NULL CHECK(event_count > 0),
            UNIQUE(device_id, sequence)
          );''');
    tx.execute('CREATE INDEX idx_command_id ON command(device_id, sequence);');
    tx.execute('''CREATE TABLE stream(
            stream_path TEXT PRIMARY KEY NOT NULL,
            version INTEGER NOT NULL
          );''');
    tx.execute('''CREATE TABLE event(
            log_position INTEGER PRIMARY KEY NOT NULL CHECK(log_position >= 0),
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            event_index INTEGER NOT NULL CHECK(event_index >= 0),
            stream_path TEXT NOT NULL,
            stream_version INTEGER NOT NULL CHECK(stream_version >= 0),
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            UNIQUE(device_id, sequence, event_index)
          );''');
    tx.execute(
      'CREATE INDEX idx_event_stream ON event(stream_path, stream_version);',
    );
    tx.execute('''CREATE UNIQUE INDEX idx_log_event_stream_version
      ON event(stream_path, stream_version);''');
  }),
);

class SqliteEventDatabase implements EventDatabase {
  final IsolateSqlite _database;

  const SqliteEventDatabase(IsolateSqlite database) : _database = database;

  @override
  int get defaultEventFetchPageSize => 50;

  Future<void> close() => _database.close();

  Future<void> migrate() => eventDatabaseMigrations.migrate(_database);

  @override
  Future<EventDatabaseState> getState() async {
    final counters = await _database.queryRow('''SELECT
      (SELECT MAX(log_position) FROM command),
      (SELECT MAX(log_position) FROM event)''');
    final vectors = await _database.query('''SELECT device_id, MAX(sequence)
      FROM command
      GROUP BY device_id
      ORDER BY device_id''');
    return EventDatabaseState(
      lastCommandLogPosition: counters![0] as int?,
      lastEventLogPosition: counters[1] as int?,
      logVersion: VersionVector({
        for (final row in vectors) row[0] as int: row[1] as int,
      }),
    );
  }

  @override
  Future<int?> getStreamVersion(String streamPath) async =>
      _database.queryValue<int?>(
        'SELECT version FROM stream WHERE stream_path = ?',
        [streamPath],
      );

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
    int count,
  ) async {
    final rows = await _database.query(
      '''SELECT
        device_id, sequence, event_index, kind, detail, occured_at, stream_version, log_position
      FROM event
      WHERE stream_path = ?
        AND stream_version >= ?
      ORDER BY stream_version ASC
      LIMIT ?;''',
      [streamPath, fromVersion, count],
    );
    final events = [
      for (final row in rows)
        StoredEvent(
          streamPath: streamPath,
          eventId: EventId(
            row.field<int>('device_id'),
            row.field<int>('sequence'),
            row.field<int>('event_index'),
          ),
          encodedEvent: EncodedEvent(
            kind: row.field<String>('kind'),
            bytes: row.field<Uint8List>('detail'),
          ),
          occuredAt: _date(row.field<int>('occured_at')),
          version: row.field<int>('stream_version'),
          position: row.field<int>('log_position'),
        ),
    ];
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.version + 1,
    );
  }

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    int fromPosition,
    int count,
  ) async {
    if (fromPosition < 0) {
      throw ArgumentError('fromPosition must be non-negative');
    }
    final rows = await _database.query(
      '''SELECT
        device_id, sequence, event_index, stream_path, kind, detail, occured_at, stream_version, log_position
      FROM event
      WHERE log_position >= ?
      ORDER BY log_position ASC
      LIMIT ?''',
      [fromPosition, count],
    );
    final events = [
      for (final row in rows)
        StoredEvent(
          streamPath: row.field<String>('stream_path'),
          eventId: EventId(
            row.field<int>('device_id'),
            row.field<int>('sequence'),
            row.field<int>('event_index'),
          ),
          encodedEvent: EncodedEvent(
            kind: row.field<String>('kind'),
            bytes: row.field<Uint8List>('detail'),
          ),
          occuredAt: _date(row.field<int>('occured_at')),
          version: row.field<int>('stream_version'),
          position: row.field<int>('log_position'),
        ),
    ];
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.position + 1,
    );
  }

  @override
  Future<GetStatisticsResult> getStatistics() async {
    final row = await _database.queryRow(
      'SELECT COUNT(*), COALESCE(SUM(LENGTH(detail)), 0) FROM event;',
    );
    return GetStatisticsResult(
      eventCount: row![0] as int,
      storageSize: row[1] as int,
    );
  }

  @override
  Future<CommandBundle?> getBundle(CommandId commandId) =>
      _database.transaction((tx) {
        final row = tx.queryRow(
          '''SELECT dependency, occured_at
          FROM command
          WHERE device_id = ?
            AND sequence = ?;''',
          [commandId.deviceId, commandId.sequence],
        );
        if (row == null) return null;
        final rows = tx.query(
          '''SELECT stream_path, kind, detail, occured_at
          FROM event
          WHERE device_id = ?
            AND sequence = ?
          ORDER BY event_index ASC;''',
          [commandId.deviceId, commandId.sequence],
        );
        return CommandBundle(
          commandId: commandId,
          dependency: _decodeVector(row.field<Uint8List>('dependency')),
          occuredAt: _date(row.field<int>('occured_at')),
          events: [
            for (final row in rows)
              BundledEvent(
                streamPath: row.field<String>('stream_path'),
                encodedEvent: EncodedEvent(
                  kind: row.field<String>('kind'),
                  bytes: row.field<Uint8List>('detail'),
                ),
                occuredAt: _date(row.field<int>('occured_at')),
              ),
          ],
        );
      });

  @override
  Future<bool> saveBundle(CommandBundle bundle) {
    if (!bundle.isValid) throw ArgumentError('invalid command bundle');
    return _database.transaction((tx) {
      final commandId = bundle.commandId;
      final logRows = tx.query('''SELECT device_id, MAX(sequence)
      FROM command
      GROUP BY device_id''');
      final frontier = VersionVector({
        for (final row in logRows) row[0] as int: row[1] as int,
      });
      if (!frontier.contains(bundle.dependency) ||
          frontier.value(commandId.deviceId) + 1 != commandId.sequence) {
        return false;
      }
      _insertLog(tx, bundle);
      return true;
    });
  }
}

void _insertLog(SyncContext tx, CommandBundle bundle) {
  final id = bundle.commandId;
  tx.execute(
    '''INSERT INTO command(log_position, device_id, sequence,
    dependency, occured_at, event_count)
    VALUES (?, ?, ?, ?, ?, ?);''',
    [
      _nextLogPosition(tx, 'command'),
      id.deviceId,
      id.sequence,
      _encodeVector(bundle.dependency),
      bundle.occuredAt.millisecondsSinceEpoch,
      bundle.events.length,
    ],
  );
  _insertLogEvents(tx, bundle);
}

int _nextLogPosition(SyncContext tx, String table) {
  final highest = tx.queryValue<int?>('SELECT MAX(log_position) FROM $table');
  return highest == null ? 0 : highest + 1;
}

void _insertLogEvents(SyncContext tx, CommandBundle bundle) {
  var logPosition = _nextLogPosition(tx, 'event');
  final versions = <String, int>{};
  for (final (index, event) in bundle.events.indexed) {
    final version =
        (versions[event.streamPath] ??
            tx.queryValue<int?>(
              'SELECT version FROM stream WHERE stream_path = ?',
              [event.streamPath],
            ) ??
            -1) +
        1;
    versions[event.streamPath] = version;
    tx.execute(
      '''INSERT INTO event(log_position, device_id, sequence,
        event_index, stream_path, stream_version, kind, detail, occured_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);''',
      [
        logPosition++,
        bundle.commandId.deviceId,
        bundle.commandId.sequence,
        index,
        event.streamPath,
        version,
        event.encodedEvent.kind,
        event.encodedEvent.bytes,
        event.occuredAt.millisecondsSinceEpoch,
      ],
    );
    _updateStreamVersion(tx, event.streamPath, version);
  }
}

void _updateStreamVersion(SyncContext tx, String streamPath, int version) {
  tx.execute(
    '''INSERT INTO stream(stream_path, version)
    VALUES (?, ?)
    ON CONFLICT(stream_path)
      DO UPDATE SET version = excluded.version;''',
    [streamPath, version],
  );
}

DateTime _date(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

Uint8List _encodeVector(VersionVector vector) =>
    JsonConverter.encode(vector.toJson());

VersionVector _decodeVector(Uint8List value) =>
    VersionVector.fromJson(JsonConverter.decode<List<dynamic>>(value));
