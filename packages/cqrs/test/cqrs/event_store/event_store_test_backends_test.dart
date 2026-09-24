import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  test('memory backend is ready without initialization', () async {
    final session = await const MemoryEventDatabaseTestBackend().open();

    expect((await session.database.getState()).lastLocalEventSequence, 0);
    expect((await session.store.getStatistics()).eventCount, 0);
    await session.close();
  });

  test('SQLite backend migrates and closes its database', () async {
    final session = await const SqliteEventDatabaseTestBackend().open();
    final database = session.database as SqliteEventDatabase;

    expect((await database.getState()).lastLocalEventSequence, 0);
    await session.close();
    await expectLater(
      database.database.queryValue<int>('SELECT 1'),
      throwsStateError,
    );
  });

  for (final backend in eventStoreTestBackends) {
    group('${backend.name} test backend', () {
      test('closes idempotently', () async {
        final session = await backend.open();

        await session.close();
        await session.close();
      });
    });
  }
}
