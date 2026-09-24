import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/log_command.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

final eventDatabaseMigrations = SqliteMigrations(
  migrationTable: 'migrations_event_database',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute('''CREATE TABLE command(
            log_position INTEGER PRIMARY KEY NOT NULL,
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
            log_position INTEGER PRIMARY KEY NOT NULL,
            device_id INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            event_index INTEGER NOT NULL CHECK(event_index >= 0),
            stream_path TEXT NOT NULL,
            stream_version INTEGER NOT NULL,
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            UNIQUE(device_id, sequence, event_index),
            CHECK((log_position < 0 AND stream_version = -1) OR
                  (log_position >= 0 AND stream_version >= 0))
          );''');
    tx.execute(
      'CREATE INDEX idx_event_stream ON event(stream_path, stream_version);',
    );
    tx.execute('''CREATE UNIQUE INDEX idx_log_event_stream_version
      ON event(stream_path, stream_version) WHERE log_position >= 0;''');
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
      (SELECT MAX(log_position) FROM command
        WHERE log_position >= 0),
      (SELECT MAX(log_position) FROM event
        WHERE log_position >= 0)''');
    final vectors = await _database.query('''SELECT device_id, MAX(sequence)
      FROM command
      WHERE log_position >= 0
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
  Future<PaginatedResult<LogEvent>> getStreamEvents(
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
        AND log_position >= 0
      ORDER BY stream_version ASC
      LIMIT ?;''',
      [streamPath, fromVersion, count],
    );
    final events = [
      for (final row in rows)
        LogEvent(
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
          logPosition: row.field<int>('log_position'),
        ),
    ];
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.version + 1,
    );
  }

  @override
  Future<PaginatedResult<LogEvent>> getLogEvents(
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
        LogEvent(
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
          logPosition: row.field<int>('log_position'),
        ),
    ];
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.logPosition + 1,
    );
  }

  @override
  Future<GetStatisticsResult> getStatistics() async {
    final row = await _database.queryRow(
      '''SELECT COUNT(*), COALESCE(SUM(LENGTH(detail)), 0)
      FROM event
      WHERE log_position >= 0;''',
    );
    return GetStatisticsResult(
      eventCount: row![0] as int,
      storageSize: row[1] as int,
    );
  }

  @override
  Future<StagedCommand?> getLogCommand(CommandId commandId) async =>
      _getCommand(commandId, isLog: true);

  @override
  Future<StagedCommand?> getStagedCommand(CommandId commandId) async =>
      _getCommand(commandId, isLog: false);

  Future<StagedCommand?> _getCommand(
    CommandId commandId, {
    required bool isLog,
  }) async {
    final adhocFilter = isLog ? 'log_position >= 0' : 'log_position < 0';

    final row = await _database.queryRow(
      '''SELECT dependency, kind, detail, started_at, completed_at, event_count
      FROM command
      WHERE device_id = ?
        AND sequence = ?
        AND $adhocFilter;''',
      [commandId.deviceId, commandId.sequence],
    );
    if (row == null) return null;

    return StagedCommand(
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
  Future<StagedEvent?> getLogEvent(EventId eventId) async =>
      _getEvent(eventId, isLog: true);

  @override
  Future<StagedEvent?> getStagedEvent(EventId eventId) async =>
      _getEvent(eventId, isLog: false);

  Future<StagedEvent?> _getEvent(EventId eventId, {required bool isLog}) async {
    final adhocFilter = isLog ? 'log_position >= 0' : 'log_position < 0';

    final row = await _database.queryRow(
      '''SELECT stream_path, kind, detail, occured_at
      FROM event
      WHERE device_id = ?
        AND sequence = ?
        AND event_index = ?
        AND $adhocFilter;''',
      [eventId.deviceId, eventId.sequence, eventId.index],
    );
    return row == null ? null : _readStagedEvent(eventId, row);
  }

  @override
  Future<List<LogCommand>> getLogCommands(int fromPosition, int count) async {
    final rows = await _database.query(
      '''SELECT log_position, device_id, sequence, dependency, kind, detail,
      started_at, completed_at, event_count
      FROM command
      WHERE log_position >= ?
      ORDER BY log_position ASC
      LIMIT ?;''',
      [fromPosition, count],
    );
    return [
      for (final row in rows)
        LogCommand(
          logPosition: row[0] as int,
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
  Future<List<LogEvent>> getLogEventsForCommand(CommandId commandId) async {
    final rows = await _database.query(
      '''SELECT event_index, stream_path, kind, detail, occured_at,
      log_position, stream_version
      FROM event
      WHERE device_id = ?
        AND sequence = ?
        AND log_position >= 0
      ORDER BY event_index ASC;''',
      [commandId.deviceId, commandId.sequence],
    );
    return [
      for (final row in rows)
        LogEvent(
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
          logPosition: row[5] as int,
          version: row[6] as int,
        ),
    ];
  }

  @override
  Future<void> appendLog(StagedCommand command, List<StagedEvent> events) =>
      _database.transaction((tx) => _insertLog(tx, command, events));

  @override
  Future<void> stageCommand(StagedCommand command) =>
      _database.transaction((tx) => _insertStagedCommand(tx, command));

  @override
  Future<void> stageEvents(List<StagedEvent> events) =>
      _database.transaction((tx) {
        var next = _nextStagedSequence(tx, 'event');
        for (var i = 0; i < events.length; i++) {
          final event = events[i];
          tx.execute(
            '''INSERT INTO event(device_id, sequence, event_index,
            stream_path, kind, detail, occured_at, log_position, stream_version)
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
  Future<bool> promoteStaged(CommandId commandId) =>
      _database.transaction((tx) {
        final command = tx.queryRow(
          '''SELECT log_position, event_count, dependency
      FROM command
      WHERE device_id = ?
        AND sequence = ?
        AND log_position < 0''',
          [commandId.deviceId, commandId.sequence],
        );
        if (command == null) return false;
        final logRows = tx.query('''SELECT device_id, MAX(sequence)
      FROM command
      WHERE log_position >= 0
      GROUP BY device_id''');
        final frontier = VersionVector({
          for (final row in logRows) row[0] as int: row[1] as int,
        });
        if (!frontier.contains(_decodeVector(command[2] as Uint8List)) ||
            frontier.value(commandId.deviceId) + 1 != commandId.sequence) {
          return false;
        }
        final events = tx.query(
          '''SELECT log_position, event_index, stream_path
          FROM event
          WHERE device_id = ?
            AND sequence = ?
            AND log_position < 0
          ORDER BY event_index ASC;''',
          [commandId.deviceId, commandId.sequence],
        );
        if (events.length != command[1] as int) return false;
        for (var i = 0; i < events.length; i++) {
          if (events[i][1] != i) return false;
        }

        final commandPosition = _nextLogPosition(tx, 'command');
        final result = tx.execute(
          '''UPDATE command SET log_position = ?
          WHERE log_position = ?
            AND log_position < 0;''',
          [commandPosition, command[0]],
        );
        if (result.modified != 1) {
          throw StateError('matching staged command does not exist');
        }
        var logPosition = _nextLogPosition(tx, 'event');
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
            SET log_position = ?, stream_version = ?
            WHERE log_position = ?
              AND log_position < 0''',
            [logPosition++, version, event[0]],
          );
          if (updated.modified != 1) {
            throw StateError('matching staged event does not exist');
          }
          _updateStreamVersion(tx, streamPath, version);
        }
        return true;
      });
}

void _insertStagedCommand(SyncContext tx, StagedCommand command) {
  final id = command.commandId;
  tx.execute(
    '''INSERT INTO command(log_position, device_id, sequence, dependency,
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

void _insertLog(
  SyncContext tx,
  StagedCommand command,
  List<StagedEvent> events,
) {
  if (events.length != command.eventCount) {
    throw StateError('log event count does not match command');
  }
  final id = command.commandId;
  tx.execute(
    '''INSERT INTO command(log_position, device_id, sequence,
    dependency, kind, detail, started_at, completed_at, event_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      _nextLogPosition(tx, 'command'),
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
  _insertLogEvents(tx, events);
}

int _nextStagedSequence(SyncContext tx, String table) {
  final lowest = tx.queryValue<int?>('SELECT MIN(log_position) FROM $table');
  return lowest == null || lowest >= 0 ? -1 : lowest - 1;
}

int _nextLogPosition(SyncContext tx, String table) {
  final highest = tx.queryValue<int?>('SELECT MAX(log_position) FROM $table');
  return highest == null || highest < 0 ? 0 : highest + 1;
}

void _insertLogEvents(SyncContext tx, List<StagedEvent> events) {
  var logPosition = _nextLogPosition(tx, 'event');
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
      '''INSERT INTO event(log_position, device_id, sequence,
        event_index, stream_path, stream_version, kind, detail, occured_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);''',
      [
        logPosition++,
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

StagedEvent _readStagedEvent(EventId eventId, Row row) => StagedEvent(
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
