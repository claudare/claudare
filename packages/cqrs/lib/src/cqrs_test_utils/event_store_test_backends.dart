import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract interface class EventStoreTestBackend {
  String get name;

  Future<EventStoreTestSession> open();
}

abstract interface class EventStoreTestSession {
  EventStore get store;
  EventDatabase get database;

  Future<List<AppliedCommand>> readAppliedCommands();

  Future<void> close();
}

class MemoryEventDatabaseTestBackend implements EventStoreTestBackend {
  final int? eventFetchPageSize;

  const MemoryEventDatabaseTestBackend({this.eventFetchPageSize});

  @override
  String get name => 'memory';

  @override
  Future<EventStoreTestSession> open() async {
    final database = MemoryEventDatabase();
    final store = EventStore(database, eventFetchPageSize: eventFetchPageSize);
    return _MemoryEventDatabaseTestSession(store, database);
  }
}

class SqliteEventDatabaseTestBackend implements EventStoreTestBackend {
  final int? eventFetchPageSize;

  const SqliteEventDatabaseTestBackend({this.eventFetchPageSize});

  @override
  String get name => 'sqlite';

  @override
  Future<EventStoreTestSession> open() async {
    final sqlite = IsolateSqlite();
    await sqlite.openInMemory();
    final database = SqliteEventDatabase(sqlite);
    try {
      await database.migrate();
    } catch (_) {
      await database.close();
      rethrow;
    }
    final store = EventStore(database, eventFetchPageSize: eventFetchPageSize);
    return _SqliteEventDatabaseTestSession(store, database);
  }
}

const eventStoreTestBackends = <EventStoreTestBackend>[
  MemoryEventDatabaseTestBackend(eventFetchPageSize: 2),
  SqliteEventDatabaseTestBackend(eventFetchPageSize: 2),
];

class _MemoryEventDatabaseTestSession implements EventStoreTestSession {
  @override
  final EventStore store;
  @override
  final MemoryEventDatabase database;

  _MemoryEventDatabaseTestSession(this.store, this.database);

  @override
  Future<List<AppliedCommand>> readAppliedCommands() =>
      database.getAppliedCommands(0, -1 >>> 1);

  @override
  Future<void> close() async {}
}

class _SqliteEventDatabaseTestSession implements EventStoreTestSession {
  @override
  final EventStore store;
  @override
  final SqliteEventDatabase database;
  Future<void>? _closeFuture;

  _SqliteEventDatabaseTestSession(this.store, this.database);

  @override
  Future<List<AppliedCommand>> readAppliedCommands() =>
      database.getAppliedCommands(0, -1 >>> 1);

  @override
  Future<void> close() => _closeFuture ??= database.close();
}
