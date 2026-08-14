import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/event/event_dependency.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract interface class EventStoreTestBackend {
  String get name;

  Future<EventStoreTestSession> open();
}

abstract interface class EventStoreTestSession {
  EventStore get store;

  Future<List<EventStoreTestCommandRecord>> readCommandRecords();

  Future<void> close();
}

class EventStoreTestCommandRecord {
  final int localSequence;
  final DeviceId deviceId;
  final int deviceSequence;
  final String kind;
  final Uint8List detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;
  final String? nackReason;
  final String? exception;

  const EventStoreTestCommandRecord({
    required this.localSequence,
    required this.deviceId,
    required this.deviceSequence,
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,
    required this.nackReason,
    required this.exception,
  });
}

class MemoryEventStoreTestBackend implements EventStoreTestBackend {
  final int? eventFetchPageSize;

  const MemoryEventStoreTestBackend({this.eventFetchPageSize});

  @override
  String get name => 'memory';

  @override
  Future<EventStoreTestSession> open() async {
    final pageSize = eventFetchPageSize;
    final store =
        pageSize == null
            ? MemoryEventStore()
            : MemoryEventStore(eventFetchPageSize: pageSize);
    return _MemoryEventStoreTestSession(store);
  }
}

class SqliteEventStoreTestBackend implements EventStoreTestBackend {
  final int eventFetchPageSize;

  const SqliteEventStoreTestBackend({required this.eventFetchPageSize});

  @override
  String get name => 'sqlite';

  @override
  Future<EventStoreTestSession> open() async {
    final database = IsolateSqlite();
    await database.openInMemory();

    final store = SqliteEventStore(
      database,
      eventFetchPageSize: eventFetchPageSize,
    );
    await store.migrate();

    return _SqliteEventStoreTestSession(store, database);
  }
}

const eventStoreTestBackends = <EventStoreTestBackend>[
  MemoryEventStoreTestBackend(eventFetchPageSize: 2),
  SqliteEventStoreTestBackend(eventFetchPageSize: 2),
];

class _MemoryEventStoreTestSession implements EventStoreTestSession {
  final MemoryEventStore _store;
  bool _closed = false;

  _MemoryEventStoreTestSession(this._store);

  @override
  EventStore get store => _store;

  @override
  Future<List<EventStoreTestCommandRecord>> readCommandRecords() async {
    return [
      for (final command in _store.testAllCommands)
        EventStoreTestCommandRecord(
          localSequence: command.localSequence,
          deviceId: command.deviceId,
          deviceSequence: command.deviceSequence,
          kind: command.kind,
          detail: command.detail,
          startedAt: command.startedAt,
          completedAt: command.completedAt,
          dependencies: command.dependencies,
          nackReason: command.nackReason,
          exception: command.exception?.toString(),
        ),
    ];
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
  }
}

class _SqliteEventStoreTestSession implements EventStoreTestSession {
  final SqliteEventStore _store;
  final IsolateSqlite _database;
  bool _closed = false;

  _SqliteEventStoreTestSession(this._store, this._database);

  @override
  EventStore get store => _store;

  @override
  Future<List<EventStoreTestCommandRecord>> readCommandRecords() async {
    final rows = await _database.query('''SELECT
      local_sequence,
      device_id,
      device_sequence,
      kind,
      detail,
      started_at,
      completed_at,
      dependencies,
      nack_reason,
      exception
    FROM command_record
    ORDER BY local_sequence ASC''');

    return [
      for (final row in rows)
        EventStoreTestCommandRecord(
          localSequence: row[0] as int,
          deviceId: DeviceId(row[1] as int),
          deviceSequence: row[2] as int,
          kind: row[3] as String,
          detail: row[4] as Uint8List,
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            row[5] as int,
            isUtc: true,
          ),
          completedAt: DateTime.fromMillisecondsSinceEpoch(
            row[6] as int,
            isUtc: true,
          ),
          dependencies: EventDependency.fromJson(
            JsonConverter.decode<List<dynamic>>(
              row[7] as Uint8List,
            ).cast<List<dynamic>>(),
          ),
          nackReason: row[8] as String?,
          exception: row[9] as String?,
        ),
    ];
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _database.close();
  }
}
