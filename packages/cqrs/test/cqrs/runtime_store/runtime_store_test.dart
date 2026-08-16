import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

typedef DatabaseSetup =
    ({RuntimeDatabase database, Future<void> Function() cleanup});

Future<void> _testRuntimeStore(
  String name,
  Future<DatabaseSetup> Function() setup,
) async {
  group('RuntimeStore - $name', () {
    late RuntimeStore store;
    late Future<void> Function() cleanup;

    setUp(() async {
      final instance = await setup();
      store = RuntimeStore(instance.database);
      await store.initialize();
      cleanup = instance.cleanup;
    });

    tearDown(() async {
      await cleanup();
    });

    test('gets zero version', () async {
      final version = await store.getRuntimeVersion('test');
      expect(version, 0);
    });

    test('sets new version', () async {
      await store.setRuntimeVersion('test', 88);
      final version = await store.getRuntimeVersion('test');
      expect(version, 88);
    });

    test('updates to version', () async {
      await store.setRuntimeVersion('test', 1);
      var version = await store.getRuntimeVersion('test');
      expect(version, 1);

      await store.setRuntimeVersion('test', 2);
      version = await store.getRuntimeVersion('test');
      expect(version, 2);
    });
  });
}

void main() async {
  await _testRuntimeStore('memory', () async {
    final database = MemoryRuntimeDatabase();
    return (database: database, cleanup: () async {});
  });

  await _testRuntimeStore('sqlite', () async {
    final database = IsolateSqlite();
    await database.openInMemory();
    return (
      database: SqliteRuntimeDatabase(database),
      cleanup: () async => database.close(),
    );
  });
}
