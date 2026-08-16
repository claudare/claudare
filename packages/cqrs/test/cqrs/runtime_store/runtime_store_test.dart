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

    test(
      'rejects non-positive migration targets without side effects',
      () async {
        for (final target in [0, -1]) {
          var invoked = false;
          await expectLater(
            store.versionMigration('test', target, () async {
              invoked = true;
            }),
            throwsArgumentError,
          );
          expect(invoked, isFalse);
          expect(await database.getRuntimeVersion('test'), 0);
        }
      },
    );

    test('stores incomplete marker while migration runs', () async {
      await store.versionMigration('test', 1, () async {
        expect(await database.getRuntimeVersion('test'), -1);
      });
      expect(await database.getRuntimeVersion('test'), 1);
    });

    test('matching completed version skips migration', () async {
      var invocationCount = 0;
      Future<void> migrate() => store.versionMigration('test', 2, () async {
        invocationCount++;
      });

      await migrate();
      await migrate();

      expect(invocationCount, 1);
      expect(await database.getRuntimeVersion('test'), 2);
    });

    test('failed migration preserves error, marker, and retries', () async {
      final error = StateError('migration failed');
      var invocationCount = 0;

      await expectLater(
        store.versionMigration('test', 3, () async {
          invocationCount++;
          throw error;
        }),
        throwsA(same(error)),
      );
      expect(await database.getRuntimeVersion('test'), -1);

      await store.versionMigration('test', 3, () async {
        invocationCount++;
      });
      expect(invocationCount, 2);
      expect(await database.getRuntimeVersion('test'), 3);
    });

    test('upgrades and downgrades both migrate', () async {
      final migratedVersions = <int>[];
      for (final version in [2, 4, 1]) {
        await store.versionMigration('test', version, () async {
          migratedVersions.add(version);
        });
      }

      expect(migratedVersions, [2, 4, 1]);
      expect(await database.getRuntimeVersion('test'), 1);
    });

    test('always policy migrates matching version', () async {
      var invocationCount = 0;
      await store.versionMigration('test', 1, () async {
        invocationCount++;
      });
      await store.versionMigration('test', 1, () async {
        invocationCount++;
      }, policy: MigrationPolicy.always);

      expect(invocationCount, 2);
      expect(await database.getRuntimeVersion('test'), 1);
    });

    test('store default always policy migrates matching version', () async {
      final alwaysStore = RuntimeStore(
        database,
        migrationPolicy: MigrationPolicy.always,
      );
      var invocationCount = 0;
      for (var i = 0; i < 2; i++) {
        await alwaysStore.versionMigration('test', 1, () async {
          invocationCount++;
        });
      }

      expect(invocationCount, 2);
    });

    test('rejects stored versions below incomplete marker', () async {
      await database.setRuntimeVersion('test', -2);

      await expectLater(
        store.versionMigration('test', 1, () async {}),
        throwsA(isA<RuntimeDatabaseException>()),
      );
      expect(await database.getRuntimeVersion('test'), -2);
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
