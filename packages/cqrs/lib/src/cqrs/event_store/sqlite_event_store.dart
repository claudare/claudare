import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/stored_command.dart';
import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

final eventDatabaseMigrations = SqliteMigrations(
  migrationTable: 'migrations_event_database',
)..add(
  SqliteMigration(1, (tx) {
    tx.execute('''CREATE TABLE command(
            log_position INTEGER PRIMARY KEY NOT NULL CHECK(log_position >= 0),
            id_actor TEXT NOT NULL,
            id_sequence INTEGER NOT NULL,
            dependency BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            event_count INTEGER NOT NULL CHECK(event_count > 0),
            UNIQUE(id_actor, id_sequence)
          );''');
    tx.execute(
      'CREATE INDEX idx_command_id ON command(id_actor, id_sequence);',
    );
    tx.execute('''CREATE TABLE stream(
            stream_path TEXT PRIMARY KEY NOT NULL,
            version INTEGER NOT NULL
          );''');
    tx.execute('''CREATE TABLE event(
            log_position INTEGER PRIMARY KEY NOT NULL CHECK(log_position >= 0),
            id_actor TEXT NOT NULL,
            id_sequence INTEGER NOT NULL,
            id_index INTEGER NOT NULL CHECK(id_index >= 0),
            stream_path TEXT NOT NULL,
            stream_version INTEGER NOT NULL CHECK(stream_version >= 0),
            kind TEXT NOT NULL,
            detail BLOB NOT NULL,
            occured_at INTEGER NOT NULL,
            UNIQUE(id_actor, id_sequence, id_index)
          );''');
    tx.execute(
      'CREATE INDEX idx_event_stream ON event(stream_path, stream_version);',
    );
    tx.execute('''CREATE UNIQUE INDEX idx_log_event_stream_version
      ON event(stream_path, stream_version);''');
  }),
);

/// Stores commands and events in SQLite transactions.
class SqliteEventStore implements EventStore {
  final IsolateSqlite _database;

  final int _eventFetchPageSize;

  SqliteEventStore(IsolateSqlite database, {int eventFetchPageSize = 10})
    : _database = database,
      _eventFetchPageSize = eventFetchPageSize {
    if (eventFetchPageSize <= 0) {
      throw ArgumentError.value(eventFetchPageSize, 'eventFetchPageSize');
    }
  }

  // FIXME: this swallows the errors
  Future<T> _transaction<T>(
    String message,
    T Function(SyncContext) action,
  ) async {
    try {
      return await _database.transaction(action);
    } on ConcurrencyProblem {
      rethrow;
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(
        EventStoreException(message, cause: cause),
        stackTrace,
      );
    }
  }

  Future<void> close() => _database.close();

  /// Creates or migrates the event schema before use.
  Future<void> migrate() => eventDatabaseMigrations.migrate(_database);

  @override
  Future<EventDatabaseState> getState() =>
      _transaction('Failed to get state', _getState);

  @override
  Future<int?> getStreamVersion(String streamPath) => _transaction(
    "Failed to get stream version for '$streamPath'",
    (tx) => _getStreamVersion(tx, streamPath),
  );

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
  ) => _transaction('Failed to get stream events', (tx) {
    if (fromVersion < 0) {
      throw ArgumentError('fromVersion must be non-negative');
    }
    final rows = tx.query(
      '''SELECT
        id_actor, id_sequence, id_index, kind, detail, occured_at, stream_version, log_position
      FROM event
      WHERE stream_path = ?
        AND stream_version >= ?
      ORDER BY stream_version ASC
      LIMIT ?;''',
      [streamPath, fromVersion, _eventFetchPageSize],
    );
    final events = [
      for (final row in rows)
        StoredEvent(
          streamPath: streamPath,
          eventId: EventId(
            row.field<String>('id_actor'),
            row.field<int>('id_sequence'),
            row.field<int>('id_index'),
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
  });

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) =>
      _transaction('Failed to get log events', (tx) {
        if (fromPosition < 0) {
          throw ArgumentError('fromPosition must be non-negative');
        }
        final rows = tx.query(
          '''SELECT
        id_actor, id_sequence, id_index, stream_path, kind, detail, occured_at, stream_version, log_position
      FROM event
      WHERE log_position >= ?
      ORDER BY log_position ASC
      LIMIT ?''',
          [fromPosition, _eventFetchPageSize],
        );
        final events = [
          for (final row in rows)
            StoredEvent(
              streamPath: row.field<String>('stream_path'),
              eventId: EventId(
                row.field<String>('id_actor'),
                row.field<int>('id_sequence'),
                row.field<int>('id_index'),
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
      });

  @override
  Future<GetStatisticsResult>
  getStatistics() => _transaction('Failed to get statistics', (tx) {
    final row = tx.queryRow(
      'SELECT COUNT(*) AS event_count, COALESCE(SUM(LENGTH(detail)), 0) AS storage_size FROM event;',
    );
    return GetStatisticsResult(
      eventCount: row!.field<int>('event_count'),
      storageSize: row.field<int>('storage_size'),
    );
  });

  @override
  Future<StoredCommand?> getStoredCommand(CommandId commandId) =>
      _transaction('Failed to get stored command $commandId', (tx) {
        final row = tx.queryRow(
          '''SELECT dependency, occured_at
          FROM command
          WHERE id_actor = ?
            AND id_sequence = ?;''',
          [commandId.actor, commandId.sequence],
        );
        if (row == null) return null;

        final rows = tx.query(
          '''SELECT stream_path, kind, detail, occured_at
          FROM event
          WHERE id_actor = ?
            AND id_sequence = ?
          ORDER BY id_index ASC;''',
          [commandId.actor, commandId.sequence],
        );

        return StoredCommand(
          commandId: commandId,
          dependency: _decodeDependency(row.field<Uint8List>('dependency')),
          occuredAt: _date(row.field<int>('occured_at')),
          events: [
            for (final row in rows)
              StoredCommandEvent(
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
  Future<void> saveChanges(CommandChanges changes) {
    return _transaction('Failed to append command batch', (tx) {
      if (changes.events.isEmpty) return;
      if (!changes.isValid()) {
        throw ArgumentError('every appended event must have one stream lock');
      }
      final state = _getState(tx);
      if (!state.logVersion.contains(changes.dependency)) {
        throw StateError('command dependency is not in the log');
      }

      for (final lock in changes.locks) {
        final current = _getStreamVersion(tx, lock.streamPath);
        if (current != lock.originatingStreamVersion) {
          throw ConcurrencyProblem();
        }
      }

      final sequence = state.logVersion.value(changes.actor) + 1;
      _append(
        tx,
        commandId: CommandId(changes.actor, sequence),
        dependency: changes.dependency,
        occuredAt: changes.occuredAt,
        events: changes.events,
      );
    });
  }

  @override
  Future<bool> addStoredCommand(StoredCommand command) =>
      _transaction('Failed to add stored command', (tx) {
        if (command.events.isEmpty) {
          throw ArgumentError('stored command must contain events');
        }
        final frontier = _getState(tx).logVersion;
        if (!frontier.contains(command.dependency) ||
            frontier.value(command.commandId.actor) + 1 !=
                command.commandId.sequence) {
          return false;
        }
        _append(
          tx,
          commandId: command.commandId,
          dependency: command.dependency,
          occuredAt: command.occuredAt,
          events: [
            for (final event in command.events)
              EventAppend(
                streamPath: event.streamPath,
                encodedEvent: event.encodedEvent,
                occuredAt: event.occuredAt,
              ),
          ],
        );
        return true;
      });

  EventDatabaseState _getState(SyncContext tx) {
    final counters =
        tx.queryRow('''SELECT
      (SELECT MAX(log_position) FROM command) AS command_position,
      (SELECT MAX(log_position) FROM event) AS event_position''')!;
    final vectors = tx.query('''SELECT id_actor, MAX(id_sequence) AS id_sequence
      FROM command
      GROUP BY id_actor
      ORDER BY id_actor;''');
    return EventDatabaseState(
      lastCommandLogPosition: counters.field<int?>('command_position'),
      lastEventLogPosition: counters.field<int?>('event_position'),
      logVersion: CommandDependency({
        for (final row in vectors)
          row.field<String>('id_actor'): row.field<int>('id_sequence'),
      }),
    );
  }

  int? _getStreamVersion(SyncContext tx, String streamPath) => tx
      .queryRow('SELECT version FROM stream WHERE stream_path = ?', [
        streamPath,
      ])
      ?.field<int>('version');

  void _append(
    SyncContext tx, {
    required CommandId commandId,
    required CommandDependency dependency,
    required DateTime occuredAt,
    required List<EventAppend> events,
  }) {
    tx.execute(
      '''INSERT INTO command(log_position, id_actor, id_sequence,
      dependency, occured_at, event_count)
      VALUES (?, ?, ?, ?, ?, ?);''',
      [
        _nextLogPosition(tx, 'command'),
        commandId.actor,
        commandId.sequence,
        _encodeDependency(dependency),
        occuredAt.millisecondsSinceEpoch,
        events.length,
      ],
    );
    _insertLogEvents(tx, commandId, events);
  }

  int _nextLogPosition(SyncContext tx, String table) {
    final highest = tx
        .queryRow('SELECT MAX(log_position) AS position FROM $table')!
        .field<int?>('position');
    return highest == null ? 0 : highest + 1;
  }

  void _insertLogEvents(
    SyncContext tx,
    CommandId commandId,
    List<EventAppend> events,
  ) {
    var logPosition = _nextLogPosition(tx, 'event');

    for (final (index, event) in events.indexed) {
      final version = (_getStreamVersion(tx, event.streamPath) ?? -1) + 1;
      tx.execute(
        '''INSERT INTO event(log_position, id_actor, id_sequence, id_index,
        stream_path, stream_version, kind, detail, occured_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);''',
        [
          logPosition++,
          commandId.actor,
          commandId.sequence,
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
}

DateTime _date(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

Uint8List _encodeDependency(CommandDependency vector) =>
    JsonConverter.encode(vector.toJson());

CommandDependency _decodeDependency(Uint8List value) =>
    CommandDependency.fromJson(
      JsonConverter.decode<Map<String, dynamic>>(value),
    );
