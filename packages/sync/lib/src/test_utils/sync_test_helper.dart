import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:sync/src/actor/sqlite_actor_identity_store.dart';
import 'package:stream_channel/stream_channel.dart';

import '../transport/transport.dart';

/// Creates SQLite stores and in-memory peer connections for tests.
abstract final class SyncTestHelper {
  /// Creates opposite ends of an in-memory connection between two actors.
  static ({PeerTransport first, PeerTransport second}) createPeerPair({
    required String firstActor,
    required String secondActor,
  }) {
    final channel = StreamChannelController<String>();
    return (
      first: PeerTransport(actor: secondActor, channel: channel.local),
      second: PeerTransport(actor: firstActor, channel: channel.foreign),
    );
  }

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
