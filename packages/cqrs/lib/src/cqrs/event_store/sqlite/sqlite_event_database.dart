import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_read.dart';
import 'package:cqrs/src/cqrs/event/stored_event_projection_read.dart';
import 'package:cqrs/src/cqrs/event_store/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event_store/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_administration.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

final eventDatabaseMigrations = SqliteMigrations(
  migrationTable: 'migrations_event_database',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute('''CREATE TABLE applied_command(
            local_sequence INTEGER PRIMARY KEY NOT NULL,
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            dependency BLOB NOT NULL,
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            started_at INTEGER NOT NULL,
            completed_at INTEGER NOT NULL,
            event_count INTEGER NOT NULL CHECK(event_count > 0),
            UNIQUE(device_id, sequence)
          );''');
    tx.execute(
      'CREATE INDEX idx_applied_command_id ON applied_command(device_id, sequence);',
    );
    tx.execute('''CREATE TABLE stream(
            stream_id TEXT PRIMARY KEY NOT NULL,
            version INTEGER NOT NULL
          );''');
    tx.execute('''CREATE TABLE event(
            local_sequence INTEGER PRIMARY KEY NOT NULL,
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            event_index INTEGER NOT NULL CHECK(event_index >= 0),
            stream_id TEXT NOT NULL,
            stream_version INTEGER NOT NULL,
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            UNIQUE(device_id, sequence, event_index),
            UNIQUE(stream_id, stream_version),
            FOREIGN KEY(device_id, sequence)
              REFERENCES applied_command(device_id, sequence)
          );''');
    tx.execute(
      'CREATE INDEX idx_event_stream ON event(stream_id, stream_version);',
    );
    tx.execute('''CREATE TABLE pending_command(
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            dependency BLOB NOT NULL,
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            started_at INTEGER NOT NULL,
            completed_at INTEGER NOT NULL,
            event_count INTEGER NOT NULL CHECK(event_count > 0),
            PRIMARY KEY(device_id, sequence)
          );''');
    tx.execute('''CREATE TABLE pending_event(
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            event_index INTEGER NOT NULL CHECK(event_index >= 0),
            stream_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            PRIMARY KEY(device_id, sequence, event_index)
          );''');
  }),
);

class SqliteEventDatabase implements EventDatabase {
  final IsolateSqlite database;

  const SqliteEventDatabase(this.database);

  @override
  int get defaultEventFetchPageSize => 50;

  @override
  Future<void> migrate() => eventDatabaseMigrations.migrate(database);

  @override
  Future<EventDatabaseState> getState() async {
    final counters = await database.queryRow('''SELECT
      (SELECT COALESCE(MAX(local_sequence), 0) FROM applied_command),
      (SELECT COALESCE(MAX(local_sequence), 0) FROM event)''');
    final vectors = await database.query(
      '''SELECT device_id, MAX(sequence) FROM applied_command
      GROUP BY device_id ORDER BY device_id''',
    );
    return EventDatabaseState(
      lastLocalCommandSequence: counters![0] as int,
      lastLocalEventSequence: counters[1] as int,
      appliedVersion: VersionVector({
        for (final row in vectors) row[0] as int: row[1] as int,
      }),
    );
  }

  @override
  Future<int> getStreamVersion(String streamId) async =>
      await database.queryValue<int?>(
        'SELECT version FROM stream WHERE stream_id = ?',
        [streamId],
      ) ??
      0;

  @override
  Future<List<StoredEventCommandRead>> getStreamEvents(
    String streamId,
    int streamVersionCursor,
    int count,
  ) async {
    final rows = await database.query(
      '''SELECT kind, detail, occured_at, stream_version FROM event
      WHERE stream_id = ? AND stream_version > ?
      ORDER BY stream_version ASC LIMIT ?''',
      [streamId, streamVersionCursor, count],
    );
    return [
      for (final row in rows)
        StoredEventCommandRead(
          encodedEvent: EncodedEvent(
            kind: row[0] as String,
            bytes: row[1] as Uint8List,
          ),
          occuredAt: _date(row[2]),
          streamVersion: row[3] as int,
        ),
    ];
  }

  @override
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int localSequenceCursor,
    int count,
  ) async {
    final filter = _sqlFilter(patternFilter);
    final rows = await database.query(
      '''SELECT stream_id, kind, detail, occured_at, local_sequence FROM event
      WHERE ${filter.sql} AND local_sequence > ?
      ORDER BY local_sequence ASC LIMIT ?''',
      [...filter.arguments, localSequenceCursor, count],
    );
    final events = [
      for (final row in rows)
        StoredEventProjectionRead(
          streamId: row[0] as String,
          encodedEvent: EncodedEvent(
            kind: row[1] as String,
            bytes: row[2] as Uint8List,
          ),
          occuredAt: _date(row[3]),
          localSequence: row[4] as int,
        ),
    ];
    return GetLocalEventsResult(
      events: events,
      sequenceNumberCursor: events.isEmpty ? null : events.last.localSequence,
    );
  }

  @override
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) async {
    final filter = _sqlFilter(patternFilter);
    final value = await database.queryValue<int?>('''SELECT local_sequence
      FROM event WHERE ${filter.sql}
      ORDER BY local_sequence DESC LIMIT 1''', filter.arguments);
    return GetLocalLastEventResult(localSequence: value ?? 0);
  }

  @override
  Future<GetStatisticsResult> getStatistics() async {
    final row = await database.queryRow(
      'SELECT COUNT(*), COALESCE(SUM(LENGTH(detail)), 0) FROM event',
    );
    return GetStatisticsResult(
      eventCount: row![0] as int,
      storageSize: row[1] as int,
    );
  }

  @override
  Future<ReplicatedCommand?> getAppliedCommand(CommandId commandId) async =>
      _getCommand('applied_command', commandId);

  @override
  Future<ReplicatedCommand?> getPendingCommand(CommandId commandId) async =>
      _getCommand('pending_command', commandId);

  Future<ReplicatedCommand?> _getCommand(
    String table,
    CommandId commandId,
  ) async {
    final row = await database.queryRow(
      '''SELECT dependency, kind, detail, started_at, completed_at, event_count
      FROM $table WHERE device_id = ? AND sequence = ?''',
      [commandId.deviceId, commandId.sequence],
    );
    if (row == null) return null;
    return ReplicatedCommand(
      commandId: commandId,
      dependency: _decodeVector(row[0] as Uint8List),
      encoded: EncodedCommand(
        kind: row[1] as String,
        bytes: row[2] as Uint8List,
      ),
      startedAt: _date(row[3]),
      completedAt: _date(row[4]),
      eventCount: row[5] as int,
    );
  }

  @override
  Future<ReplicatedEvent?> getAppliedEvent(EventId eventId) async =>
      _getEvent('event', eventId);

  @override
  Future<ReplicatedEvent?> getPendingEvent(EventId eventId) async =>
      _getEvent('pending_event', eventId);

  Future<ReplicatedEvent?> _getEvent(String table, EventId eventId) async {
    final row = await database.queryRow(
      '''SELECT stream_id, kind, detail, occured_at FROM $table
      WHERE device_id = ? AND sequence = ? AND event_index = ?''',
      [eventId.deviceId, eventId.sequence, eventId.index],
    );
    return row == null ? null : _readReplicatedEvent(eventId, row);
  }

  @override
  Future<List<ReplicatedEvent>> getPendingEvents(CommandId commandId) async {
    final rows = await database.query(
      '''SELECT event_index, stream_id, kind, detail, occured_at
      FROM pending_event WHERE device_id = ? AND sequence = ?
      ORDER BY event_index ASC''',
      [commandId.deviceId, commandId.sequence],
    );
    return [
      for (final row in rows)
        ReplicatedEvent(
          eventId: EventId(
            commandId.deviceId,
            commandId.sequence,
            row[0] as int,
          ),
          streamId: row[1] as String,
          encodedEvent: EncodedEvent(
            kind: row[2] as String,
            bytes: row[3] as Uint8List,
          ),
          occuredAt: _date(row[4]),
        ),
    ];
  }

  @override
  Future<List<AppliedCommand>> getAppliedCommands(
    int localSequenceCursor,
    int count,
  ) async {
    final rows = await database.query(
      '''SELECT local_sequence, device_id, sequence, dependency, kind, detail,
      started_at, completed_at, event_count FROM applied_command
      WHERE local_sequence > ? ORDER BY local_sequence ASC LIMIT ?''',
      [localSequenceCursor, count],
    );
    return [
      for (final row in rows)
        AppliedCommand(
          localSequence: row[0] as int,
          commandId: CommandId(row[1] as int, row[2] as int),
          dependency: _decodeVector(row[3] as Uint8List),
          encoded: EncodedCommand(
            kind: row[4] as String,
            bytes: row[5] as Uint8List,
          ),
          startedAt: _date(row[6]),
          completedAt: _date(row[7]),
          eventCount: row[8] as int,
        ),
    ];
  }

  @override
  Future<List<AppliedEvent>> getAppliedEvents(CommandId commandId) async {
    final rows = await database.query(
      '''SELECT event_index, stream_id, kind, detail, occured_at,
      local_sequence, stream_version FROM event
      WHERE device_id = ? AND sequence = ? ORDER BY event_index ASC''',
      [commandId.deviceId, commandId.sequence],
    );
    return [
      for (final row in rows)
        AppliedEvent(
          eventId: EventId(
            commandId.deviceId,
            commandId.sequence,
            row[0] as int,
          ),
          streamId: row[1] as String,
          encodedEvent: EncodedEvent(
            kind: row[2] as String,
            bytes: row[3] as Uint8List,
          ),
          occuredAt: _date(row[4]),
          localSequence: row[5] as int,
          streamVersion: row[6] as int,
        ),
    ];
  }

  @override
  Future<void> appendApplied(
    AppliedCommand command,
    List<AppliedEvent> events,
  ) => database.transaction((tx) => _insertApplied(tx, command, events));

  @override
  Future<void> stagePendingCommand(ReplicatedCommand command) =>
      database.transaction((tx) => _insertPendingCommand(tx, command));

  @override
  Future<void> stagePendingEvents(List<ReplicatedEvent> events) =>
      database.transaction((tx) {
        for (final event in events) {
          tx.execute(
            '''INSERT INTO pending_event(device_id, sequence, event_index,
            stream_id, kind, detail, occured_at) VALUES (?, ?, ?, ?, ?, ?, ?)''',
            [
              event.eventId.deviceId,
              event.eventId.sequence,
              event.eventId.index,
              event.streamId,
              event.encodedEvent.kind,
              event.encodedEvent.bytes,
              event.occuredAt.millisecondsSinceEpoch,
            ],
          );
        }
      });

  @override
  Future<void> promotePending(
    AppliedCommand command,
    List<AppliedEvent> events,
  ) => database.transaction((tx) {
    _insertApplied(tx, command, events);
    final id = command.commandId;
    tx.execute(
      'DELETE FROM pending_event WHERE device_id = ? AND sequence = ?',
      [id.deviceId, id.sequence],
    );
    final result = tx.execute(
      'DELETE FROM pending_command WHERE device_id = ? AND sequence = ?',
      [id.deviceId, id.sequence],
    );
    if (result.modified != 1) {
      throw StateError('matching pending command does not exist');
    }
  });

  @override
  Future<void> reset() => database.transaction((tx) {
    tx.execute('DELETE FROM pending_event');
    tx.execute('DELETE FROM pending_command');
    tx.execute('DELETE FROM event');
    tx.execute('DELETE FROM applied_command');
    tx.execute('DELETE FROM stream');
  });
}

void _insertPendingCommand(SyncContext tx, ReplicatedCommand command) {
  final id = command.commandId;
  tx.execute(
    '''INSERT INTO pending_command(device_id, sequence, dependency, kind,
    detail, started_at, completed_at, event_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      id.deviceId,
      id.sequence,
      _encodeVector(command.dependency),
      command.encoded.kind,
      command.encoded.bytes,
      command.startedAt.millisecondsSinceEpoch,
      command.completedAt.millisecondsSinceEpoch,
      command.eventCount,
    ],
  );
}

void _insertApplied(
  SyncContext tx,
  AppliedCommand command,
  List<AppliedEvent> events,
) {
  final id = command.commandId;
  tx.execute(
    '''INSERT INTO applied_command(local_sequence, device_id, sequence,
    dependency, kind, detail, started_at, completed_at, event_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      command.localSequence,
      id.deviceId,
      id.sequence,
      _encodeVector(command.dependency),
      command.encoded.kind,
      command.encoded.bytes,
      command.startedAt.millisecondsSinceEpoch,
      command.completedAt.millisecondsSinceEpoch,
      command.eventCount,
    ],
  );
  for (final event in events) {
    tx.execute(
      '''INSERT INTO event(local_sequence, device_id, sequence, event_index,
      stream_id, stream_version, kind, detail, occured_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        event.localSequence,
        event.eventId.deviceId,
        event.eventId.sequence,
        event.eventId.index,
        event.streamId,
        event.streamVersion,
        event.encodedEvent.kind,
        event.encodedEvent.bytes,
        event.occuredAt.millisecondsSinceEpoch,
      ],
    );
    tx.execute(
      '''INSERT INTO stream(stream_id, version) VALUES (?, ?)
      ON CONFLICT(stream_id) DO UPDATE SET version = excluded.version''',
      [event.streamId, event.streamVersion],
    );
  }
}

ReplicatedEvent _readReplicatedEvent(EventId eventId, Row row) =>
    ReplicatedEvent(
      eventId: eventId,
      streamId: row[0] as String,
      encodedEvent: EncodedEvent(
        kind: row[1] as String,
        bytes: row[2] as Uint8List,
      ),
      occuredAt: _date(row[3]),
    );

DateTime _date(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

Uint8List _encodeVector(VersionVector vector) =>
    JsonConverter.encode(vector.toJson());

VersionVector _decodeVector(Uint8List value) =>
    VersionVector.fromJson(JsonConverter.decode<List<dynamic>>(value));

({String sql, List<Object?> arguments}) _sqlFilter(PatternFilter filter) {
  switch (filter.type) {
    case PatternFilterType.any:
      return (sql: '1 = 1', arguments: []);
    case PatternFilterType.exact:
      return (sql: 'stream_id = ?', arguments: [filter.pattern]);
    case PatternFilterType.startsWith:
      return (sql: 'stream_id LIKE ?', arguments: ['${filter.pattern}%']);
  }
}
