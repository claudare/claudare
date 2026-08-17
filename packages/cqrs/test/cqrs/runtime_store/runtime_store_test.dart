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
    late RuntimeDatabase database;
    late Future<void> Function() cleanup;

    setUp(() async {
      final instance = await setup();
      database = instance.database;
      store = RuntimeStore(database);
      await store.initialize();
      cleanup = instance.cleanup;
    });

    tearDown(() async {
      await cleanup();
    });

    test('projection is initially not initialized', () async {
      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionNotInitialized>(),
      );
    });

    test('reset persists version and initializes progress at zero', () async {
      var reset = false;
      await store.resetProjection('projection', 3, () async {
        reset = true;
      });

      expect(reset, isTrue);
      final position =
          await store.getProjectionPosition('projection')
              as ProjectionAtSequence;
      expect(position.version, 3);
      expect(position.scannedThroughLocalSequence, 0);
    });

    test('rejects non-positive reset versions without side effects', () async {
      for (final version in [0, -1]) {
        var invoked = false;
        await expectLater(
          store.resetProjection('projection', version, () async {
            invoked = true;
          }),
          throwsA(isA<RuntimeStoreException>()),
        );
        expect(invoked, isFalse);
      }
      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionNotInitialized>(),
      );
    });

    test('page advancement preserves version and stores page target', () async {
      await store.resetProjection('projection', 4, () async {});
      var applied = false;
      await store.advanceProjection('projection', 0, 7, () async {
        applied = true;
      });

      expect(applied, isTrue);
      final position =
          await store.getProjectionPosition('projection')
              as ProjectionAtSequence;
      expect(position.version, 4);
      expect(position.scannedThroughLocalSequence, 7);
    });

    test('advances over skipped sequences with an empty action', () async {
      await store.resetProjection('projection', 1, () async {});

      await store.advanceProjection('projection', 0, 12, () async {});

      final position =
          await store.getProjectionPosition('projection')
              as ProjectionAtSequence;
      expect(position.scannedThroughLocalSequence, 12);
    });

    test('records applying and scanned boundaries around one page', () async {
      await store.resetProjection('projection', 2, () async {});

      await store.advanceProjection('projection', 0, 5, () async {
        final state = await database.getProjectionState('projection');
        expect(state?.version, 2);
        expect(state?.applyingThroughLocalSequence, 5);
        expect(state?.scannedThroughLocalSequence, 0);
      });

      final state = await database.getProjectionState('projection');
      expect(state?.applyingThroughLocalSequence, 5);
      expect(state?.scannedThroughLocalSequence, 5);
    });

    test('rejects an incorrect current cursor', () async {
      await store.resetProjection('projection', 1, () async {});

      await expectLater(
        store.advanceProjection('projection', 1, 2, () async {}),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects negative and non-advancing sequences', () async {
      await store.resetProjection('projection', 1, () async {});

      await expectLater(
        store.advanceProjection('projection', -1, 1, () async {}),
        throwsA(isA<RuntimeStoreException>()),
      );
      await expectLater(
        store.advanceProjection('projection', 0, -1, () async {}),
        throwsA(isA<RuntimeStoreException>()),
      );
      await expectLater(
        store.advanceProjection('projection', 0, 0, () async {}),
        throwsA(isA<RuntimeStoreException>()),
      );
    });

    test(
      'failed reset preserves target version and incomplete state',
      () async {
        final error = StateError('reset failed');

        await expectLater(
          store.resetProjection('projection', 6, () async => throw error),
          throwsA(same(error)),
        );
        expect(
          await store.getProjectionPosition('projection'),
          isA<ProjectionInconsistent>(),
        );
        final state = await database.getProjectionState('projection');
        expect(state?.version, 6);
        expect(state?.applyingThroughLocalSequence, 0);
        expect(state?.scannedThroughLocalSequence, isNull);
      },
    );

    test('failed page preserves interrupted boundaries', () async {
      await store.resetProjection('projection', 2, () async {});
      final error = StateError('page failed');

      await expectLater(
        store.advanceProjection('projection', 0, 4, () async => throw error),
        throwsA(same(error)),
      );
      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionInconsistent>(),
      );
      final state = await database.getProjectionState('projection');
      expect(state?.version, 2);
      expect(state?.applyingThroughLocalSequence, 4);
      expect(state?.scannedThroughLocalSequence, 0);
    });

    test('detects persisted interrupted boundaries', () async {
      await database.setProjectionState(
        'projection',
        const RuntimeProjectionState(
          version: 1,
          applyingThroughLocalSequence: 8,
          scannedThroughLocalSequence: 3,
        ),
      );

      expect(
        await store.getProjectionPosition('projection'),
        isA<ProjectionInconsistent>(),
      );
    });

    test('reset is inconsistent while its action runs', () async {
      await store.resetProjection('projection', 1, () async {});

      await store.resetProjection('projection', 2, () async {
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
