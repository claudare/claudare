import 'package:core/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

// TODO: refactor to this pattern:
/*
typedef RepoSetup = ({RuntimeRepo repo, Future<void> Function() cleanup});

Future<RepoSetup> createMemoryRuntimeRepo() async {
  final repo = MemoryRuntimeRepo();
  await repo.initialize();
  return (
    repo: repo,
    cleanup: () async {},
  );
}

Future<RepoSetup> createSqliteRuntimeRepo() async {
  final db = IsolateSqlite(IsolateSqlite.memoryInitFn);
  await db.open();
  final repo = SqliteRuntimeRepo(db);
  await repo.initialize();
  return (
    repo: repo,
    cleanup: () async => await db.close(),
  );
}

List<(String, Future<RepoSetup> Function())> getRuntimeRepoFactories() {
  return [
    ('memory', createMemoryRuntimeRepo),
    ('sqlite', createSqliteRuntimeRepo),
  ];
}
*/

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

  // TODO: this could initialize multiple times.
  // This is an ugly pattern
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

List<EventStoreFactory> getEventStoreFactories() {
  return [MemoryEventStoreFactory(), SqlEventStoreFactory()];
}
