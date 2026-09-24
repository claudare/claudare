import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
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
    tx.execute('CREATE INDEX idx_command_id ON command(device_id, sequence);');
    tx.execute('''CREATE TABLE stream(
            stream_path TEXT PRIMARY KEY NOT NULL,
            version INTEGER NOT NULL
          );''');
    tx.execute('''CREATE TABLE event(
            local_sequence INTEGER PRIMARY KEY NOT NULL,
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            event_index INTEGER NOT NULL CHECK(event_index >= 0),
            stream_path TEXT NOT NULL,
            stream_version INTEGER NOT NULL,
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            UNIQUE(device_id, sequence, event_index),
            CHECK((local_sequence < 0 AND stream_version = -1) OR
                  (local_sequence >= 0 AND stream_version >= 0))
          );''');
    tx.execute(
      'CREATE INDEX idx_event_stream ON event(stream_path, stream_version);',
    );
    tx.execute('''CREATE UNIQUE INDEX idx_applied_event_stream_version
      ON event(stream_path, stream_version) WHERE local_sequence >= 0;''');
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
      (SELECT MAX(local_sequence) FROM command
        WHERE local_sequence >= 0),
      (SELECT MAX(local_sequence) FROM event
        WHERE local_sequence >= 0)''');
    final vectors = await _database.query('''SELECT device_id, MAX(sequence)
      FROM command
      WHERE local_sequence >= 0
      GROUP BY device_id
      ORDER BY device_id''');
    return EventDatabaseState(
      lastLocalCommandSequence: counters![0] as int?,
      lastLocalEventSequence: counters[1] as int?,
      appliedVersion: VersionVector({
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
    int streamVersionCursor,
    int count,
  ) async {
    final rows = await _database.query(
      '''SELECT
        device_id, sequence, event_index, kind, detail, occured_at, stream_version, local_sequence
      FROM event
      WHERE stream_path = ?
        AND stream_version >= ?
        AND local_sequence >= 0
      ORDER BY stream_version ASC
      LIMIT ?;''',
      [streamPath, streamVersionCursor, count],
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
          localSequence: row.field<int>('local_sequence'),
        ),
    ];
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.version + 1,
    );
  }

  @override
  Future<PaginatedResult<StoredEvent>> getLocalEvents(
    int localSequenceCursor,
    int count,
  ) async {
    if (localSequenceCursor < 0) {
      throw ArgumentError('localSequenceCursor must be non-negative');
    }
    final rows = await _database.query(
      '''SELECT
        device_id, sequence, event_index, stream_path, kind, detail, occured_at, stream_version, local_sequence
      FROM event
      WHERE local_sequence >= ?
      ORDER BY local_sequence ASC
      LIMIT ?''',
      [localSequenceCursor, count],
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
          localSequence: row.field<int>('local_sequence'),
        ),
    ];
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.localSequence + 1,
    );
  }

  @override
  Future<GetStatisticsResult> getStatistics() async {
    final row = await _database.queryRow(
      '''SELECT COUNT(*), COALESCE(SUM(LENGTH(detail)), 0)
      FROM event
      WHERE local_sequence >= 0;''',
    );
    return GetStatisticsResult(
      eventCount: row![0] as int,
      storageSize: row[1] as int,
    );
  }

  @override
  Future<ReplicatedCommand?> getAppliedCommand(CommandId commandId) async =>
      _getCommand(commandId, isApplied: true);

  @override
  Future<ReplicatedCommand?> getPendingCommand(CommandId commandId) async =>
      _getCommand(commandId, isApplied: false);

  Future<ReplicatedCommand?> _getCommand(
    CommandId commandId, {
    required bool isApplied,
  }) async {
    final adhocFilter =
        isApplied ? 'local_sequence >= 0' : 'local_sequence < 0';

    final row = await _database.queryRow(
      '''SELECT dependency, kind, detail, started_at, completed_at, event_count
      FROM command
      WHERE device_id = ?
        AND sequence = ?
        AND $adhocFilter;''',
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
      _getEvent(eventId, isApplied: true);

  @override
  Future<ReplicatedEvent?> getPendingEvent(EventId eventId) async =>
      _getEvent(eventId, isApplied: false);

  Future<ReplicatedEvent?> _getEvent(
    EventId eventId, {
    required bool isApplied,
  }) async {
    final adhocFilter =
        isApplied ? 'local_sequence >= 0' : 'local_sequence < 0';

    final row = await _database.queryRow(
      '''SELECT stream_path, kind, detail, occured_at
      FROM event
      WHERE device_id = ?
        AND sequence = ?
        AND event_index = ?
        AND $adhocFilter;''',
      [eventId.deviceId, eventId.sequence, eventId.index],
    );
    return row == null ? null : _readReplicatedEvent(eventId, row);
  }

  @override
  Future<List<AppliedCommand>> getAppliedCommands(
    int localSequenceCursor,
    int count,
  ) async {
    final rows = await _database.query(
      '''SELECT local_sequence, device_id, sequence, dependency, kind, detail,
      started_at, completed_at, event_count
      FROM command
      WHERE local_sequence >= ?
      ORDER BY local_sequence ASC
      LIMIT ?;''',
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
  Future<List<StoredEvent>> getAppliedEvents(CommandId commandId) async {
    final rows = await _database.query(
      '''SELECT event_index, stream_path, kind, detail, occured_at,
      local_sequence, stream_version
      FROM event
      WHERE device_id = ?
        AND sequence = ?
        AND local_sequence >= 0
      ORDER BY event_index ASC;''',
      [commandId.deviceId, commandId.sequence],
    );
    return [
      for (final row in rows)
        StoredEvent(
          eventId: EventId(
            commandId.deviceId,
            commandId.sequence,
            row[0] as int,
          ),
          streamPath: row[1] as String,
          encodedEvent: EncodedEvent(
            kind: row[2] as String,
            bytes: row[3] as Uint8List,
          ),
          occuredAt: _date(row[4]),
          localSequence: row[5] as int,
          version: row[6] as int,
        ),
    ];
  }

  @override
  Future<void> appendApplied(
    ReplicatedCommand command,
    List<ReplicatedEvent> events,
  ) => _database.transaction((tx) => _insertApplied(tx, command, events));

  @override
  Future<void> stagePendingCommand(ReplicatedCommand command) =>
      _database.transaction((tx) => _insertPendingCommand(tx, command));

  @override
  Future<void> stagePendingEvents(List<ReplicatedEvent> events) =>
      _database.transaction((tx) {
        var next = _nextStagedSequence(tx, 'event');
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          tx.execute(
            '''INSERT INTO event(device_id, sequence, event_index,
            stream_path, kind, detail, occured_at, local_sequence, stream_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, -1)''',
            [
              event.eventId.deviceId,
              event.eventId.sequence,
              event.eventId.index,
              event.streamPath,
              event.encodedEvent.kind,
              event.encodedEvent.bytes,
              event.occuredAt.millisecondsSinceEpoch,
              next--,
            ],
          );
        }
      });

  @override
  Future<bool> promotePending(CommandId commandId) =>
      _database.transaction((tx) {
        final command = tx.queryRow(
          '''SELECT local_sequence, event_count, dependency
      FROM command
      WHERE device_id = ?
        AND sequence = ?
        AND local_sequence < 0''',
          [commandId.deviceId, commandId.sequence],
        );
        if (command == null) return false;
        final appliedRows = tx.query('''SELECT device_id, MAX(sequence)
      FROM command
      WHERE local_sequence >= 0
      GROUP BY device_id''');
        final frontier = VersionVector({
          for (final row in appliedRows) row[0] as int: row[1] as int,
        });
        if (!frontier.contains(_decodeVector(command[2] as Uint8List)) ||
            frontier.value(commandId.deviceId) + 1 != commandId.sequence) {
          return false;
        }
        final events = tx.query(
          '''SELECT local_sequence, event_index, stream_path
          FROM event
          WHERE device_id = ?
            AND sequence = ?
            AND local_sequence < 0
          ORDER BY event_index ASC;''',
          [commandId.deviceId, commandId.sequence],
        );
        if (events.length != command[1] as int) return false;
        for (var i = 0; i < events.length; i++) {
          if (events[i][1] != i) return false;
        }

        final commandSequence = _nextAppliedSequence(tx, 'command');
        final result = tx.execute(
          '''UPDATE command SET local_sequence = ?
          WHERE local_sequence = ?
            AND local_sequence < 0;''',
          [commandSequence, command[0]],
        );
        if (result.modified != 1) {
          throw StateError('matching pending command does not exist');
        }
        var localSequence = _nextAppliedSequence(tx, 'event');
        final versions = <String, int>{};
        for (final event in events) {
          final streamPath = event[2] as String;
          final version =
              (versions[streamPath] ??
                  tx.queryValue<int?>(
                    'SELECT version FROM stream WHERE stream_path = ?',
                    [streamPath],
                  ) ??
                  -1) +
              1;
          versions[streamPath] = version;
          final updated = tx.execute(
            '''UPDATE event
            SET local_sequence = ?, stream_version = ?
            WHERE local_sequence = ?
              AND local_sequence < 0''',
            [localSequence++, version, event[0]],
          );
          if (updated.modified != 1) {
            throw StateError('matching pending event does not exist');
          }
          _updateStreamVersion(tx, streamPath, version);
        }
        return true;
      });
}

void _insertPendingCommand(SyncContext tx, ReplicatedCommand command) {
  final id = command.commandId;
  tx.execute(
    '''INSERT INTO command(local_sequence, device_id, sequence, dependency,
    kind, detail, started_at, completed_at, event_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      _nextStagedSequence(tx, 'command'),
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
  ReplicatedCommand command,
  List<ReplicatedEvent> events,
) {
  if (events.length != command.eventCount) {
    throw StateError('applied event count does not match command');
  }
  final id = command.commandId;
  tx.execute(
    '''INSERT INTO command(local_sequence, device_id, sequence,
    dependency, kind, detail, started_at, completed_at, event_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      _nextAppliedSequence(tx, 'command'),
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
  _insertAppliedEvents(tx, events);
}

int _nextStagedSequence(SyncContext tx, String table) {
  final lowest = tx.queryValue<int?>('SELECT MIN(local_sequence) FROM $table');
  return lowest == null || lowest >= 0 ? -1 : lowest - 1;
}

int _nextAppliedSequence(SyncContext tx, String table) {
  final highest = tx.queryValue<int?>('SELECT MAX(local_sequence) FROM $table');
  return highest == null || highest < 0 ? 0 : highest + 1;
}

void _insertAppliedEvents(SyncContext tx, List<ReplicatedEvent> events) {
  var localSequence = _nextAppliedSequence(tx, 'event');
  final versions = <String, int>{};
  for (final (index, event) in events.indexed) {
    if (event.eventId.index != index) {
      throw StateError('event index is invalid');
    }
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
      '''INSERT INTO event(local_sequence, device_id, sequence,
        event_index, stream_path, stream_version, kind, detail, occured_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);''',
      [
        localSequence++,
        event.eventId.deviceId,
        event.eventId.sequence,
        event.eventId.index,
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

ReplicatedEvent _readReplicatedEvent(EventId eventId, Row row) =>
    ReplicatedEvent(
      eventId: eventId,
      streamPath: row[0] as String,
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
