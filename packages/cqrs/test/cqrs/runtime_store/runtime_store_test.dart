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

    test('projection is initially not initialized', () async {
      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionNotInitialized>(),
      );
    });

    test('reset establishes sequence zero', () async {
      var reset = false;
      await store.resetProjection('projection', () async {
        reset = true;
      });

      expect(reset, isTrue);
      final position = await store.getProjectionPosition('projection');
      expect(position, isA<ProjectionAtSequence>());
      expect((position as ProjectionAtSequence).sequence, 0);
    });

    test('advances over skipped global sequences', () async {
      await store.resetProjection('projection', () async {});
      var applied = false;
      await store.advanceProjection('projection', 0, 7, () async {
        applied = true;
      });

      expect(applied, isTrue);
      final position =
          await store.getProjectionPosition('projection')
              as ProjectionAtSequence;
      expect(position.sequence, 7);
    });

    test('rejects an incorrect current sequence', () async {
      await store.resetProjection('projection', () async {});

      await expectLater(
        store.advanceProjection('projection', 1, 2, () async {}),
        throwsStateError,
      );
    });

    test('rejects negative and non-advancing sequences', () async {
      await store.resetProjection('projection', () async {});

      await expectLater(
        store.advanceProjection('projection', -1, 1, () async {}),
        throwsArgumentError,
      );
      await expectLater(
        store.advanceProjection('projection', 0, -1, () async {}),
        throwsArgumentError,
      );
      await expectLater(
        store.advanceProjection('projection', 0, 0, () async {}),
        throwsArgumentError,
      );
    });

    test('reset failure stays inconsistent and preserves the error', () async {
      final error = StateError('reset failed');

      await expectLater(
        store.resetProjection('projection', () async => throw error),
        throwsA(same(error)),
      );
      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionInconsistent>(),
      );
    });

    test('apply failure stays inconsistent and preserves the error', () async {
      await store.resetProjection('projection', () async {});
      final error = StateError('apply failed');

      await expectLater(
        store.advanceProjection('projection', 0, 4, () async => throw error),
        throwsA(same(error)),
      );
      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionInconsistent>(),
      );
    });

    test('reset at zero is inconsistent while reset runs', () async {
      await store.resetProjection('projection', () async {});

      await store.resetProjection('projection', () async {
        expect(
          await store.getProjectionPosition('projection'),
          isA<ProjectionInconsistent>(),
        );
      });
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
