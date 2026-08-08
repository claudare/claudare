import 'package:core/cqrs.dart';
import 'package:core/src/cqrs/cqrs_runtime/runtime_repo/safe_runtime_repo.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

typedef RepoSetup = ({RuntimeRepo repo, Future<void> Function() cleanup});

Future<void> _testRuntimeRepo(
  String name,
  Future<RepoSetup> Function() setup,
) async {
  group('RuntimeRepo - $name', () {
    late SafeRuntimeRepo repo;
    late Future<void> Function() cleanup;

    setUp(() async {
      final instance = await setup();
      repo = SafeRuntimeRepo(instance.repo);
      cleanup = instance.cleanup;
    });

    tearDown(() async {
      await cleanup();
    });

    test('gets zero version', () async {
      final version = await repo.getRuntimeVersion('test');
      expect(version, 0);
    });

    test('sets new version', () async {
      await repo.setRuntimeVersion('test', 88);
      final version = await repo.getRuntimeVersion('test');
      expect(version, 88);
    });

    test('updates to version', () async {
      await repo.setRuntimeVersion('test', 1);
      var version = await repo.getRuntimeVersion('test');
      expect(version, 1);

      await repo.setRuntimeVersion('test', 2);
      final updatedVersion = await repo.getRuntimeVersion('test');
      expect(updatedVersion, 2);
    });
  });
}

void main() async {
  await _testRuntimeRepo('memory', () async {
    final repo = MemoryRuntimeRepo();
    await repo.initialize();
    return (repo: repo, cleanup: () async {});
  });

  await _testRuntimeRepo('sqlite', () async {
    final db = IsolateSqlite();
    await db.openInMemory();
    final repo = SqliteRuntimeRepo(db);
    await repo.initialize();
    return (repo: repo, cleanup: () async => await db.close());
  });
}
