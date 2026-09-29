import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:sync/src/actor/sqlite_actor_identity_store.dart';

/// Creates ready SQLite stores for tests.
abstract final class SyncTestHelper {
  /// Opens and migrates an in-memory store. The caller must close the store.
  static Future<SqliteActorIdentityStore>
  createMemoryActorIdentityStore() async {
    final database = IsolateSqlite();
    await database.openInMemory();
    try {
      final store = SqliteActorIdentityStore(database);
      await store.migrate();
      return store;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
}
