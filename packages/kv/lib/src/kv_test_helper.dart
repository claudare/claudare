import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:kv/src/sqlite_kv.dart';

/// Creates ready SQLite KV stores for tests.
abstract final class KvTestHelper {
  /// Opens and migrates an in-memory store. The caller must close the store.
  static Future<SqliteKv> createMemoryKv() async {
    final database = IsolateSqlite();
    await database.openInMemory();
    try {
      final store = SqliteKv(database);
      await store.migrate();
      return store;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
}
