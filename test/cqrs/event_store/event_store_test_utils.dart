import 'package:core/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract interface class EventStoreFactory {
  String get name;
  Future<EventStore> create();
  Future<void> cleanup();
}

class MemoryEventStoreFactory implements EventStoreFactory {
  @override
  String get name => 'InMemory';

  @override
  Future<EventStore> create() async {
    return MemoryEventStore();
  }

  @override
  Future<void> cleanup() async {}
}

class SqlEventStoreFactory implements EventStoreFactory {
  @override
  String get name => 'SQLite';

  late IsolateSqlite _db;

  @override
  Future<EventStore> create() async {
    _db = IsolateSqlite(IsolateSqlite.memoryInitFn);
    await _db.open();

    final es = SqliteEventStore(_db);

    await es.migrate();

    return es;
  }

  @override
  Future<void> cleanup() async {
    await _db.close();
  }
}

final eventStoreImplementations = [
  MemoryEventStoreFactory(),
  SqlEventStoreFactory(),
];
