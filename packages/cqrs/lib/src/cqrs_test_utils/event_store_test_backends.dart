import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract interface class EventStoreTestBackend {
  String get name;
  Future<EventStoreTestSession> open();
}

abstract interface class EventStoreTestSession {
  EventStore get store;
  Future<void> close();
}

class MemoryEventStoreTestBackend implements EventStoreTestBackend {
  final int? eventFetchPageSize;
  const MemoryEventStoreTestBackend({this.eventFetchPageSize});

  @override
  String get name => 'memory';

  @override
  Future<EventStoreTestSession> open() async => _MemoryEventStoreTestSession(
    eventFetchPageSize == null
        ? MemoryEventStore()
        : MemoryEventStore(eventFetchPageSize: eventFetchPageSize!),
  );
}

class SqliteEventStoreTestBackend implements EventStoreTestBackend {
  final int? eventFetchPageSize;
  const SqliteEventStoreTestBackend({this.eventFetchPageSize});

  @override
  String get name => 'sqlite';

  @override
  Future<EventStoreTestSession> open() async {
    final sqlite = IsolateSqlite();
    await sqlite.openInMemory();
    try {
      final store =
          eventFetchPageSize == null
              ? SqliteEventStore(sqlite)
              : SqliteEventStore(
                sqlite,
                eventFetchPageSize: eventFetchPageSize!,
              );
      await store.migrate();
      return _SqliteEventStoreTestSession(store);
    } catch (_) {
      await sqlite.close();
      rethrow;
    }
  }
}

const eventStoreTestBackends = <EventStoreTestBackend>[
  MemoryEventStoreTestBackend(eventFetchPageSize: 2),
  SqliteEventStoreTestBackend(eventFetchPageSize: 2),
];

class _MemoryEventStoreTestSession implements EventStoreTestSession {
  @override
  final MemoryEventStore store;
  _MemoryEventStoreTestSession(this.store);

  @override
  Future<void> close() async {}
}

class _SqliteEventStoreTestSession implements EventStoreTestSession {
  @override
  final SqliteEventStore store;
  Future<void>? _closeFuture;
  _SqliteEventStoreTestSession(this.store);

  @override
  Future<void> close() => _closeFuture ??= store.close();
}
