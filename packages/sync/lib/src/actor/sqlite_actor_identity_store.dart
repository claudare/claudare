import 'dart:typed_data';

import 'package:claudare_crypto/crypto.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:sync/src/actor/actor_identity_store.dart';

final _actorIdentityMigrations =
    SqliteMigrations(migrationTable: 'migrations_sync_actor_identity')..add(
      SqliteMigration(1, (tx) {
        tx.execute('''CREATE TABLE sync_local_actor_identity(
          id INTEGER PRIMARY KEY CHECK(id = 1),
          public_key BLOB NOT NULL
        );''');
        tx.execute('''CREATE TABLE sync_peer_actor_identity(
          public_key BLOB PRIMARY KEY NOT NULL
        );''');
      }),
    );

/// Persists local and peer identities in an injected SQLite database.
class SqliteActorIdentityStore implements ActorIdentityStore {
  final IsolateSqlite _database;

  SqliteActorIdentityStore(IsolateSqlite database) : _database = database;

  /// Creates or migrates the identity schema before use.
  Future<void> migrate() => _actorIdentityMigrations.migrate(_database);

  /// Closes the supplied database after its consumers have stopped.
  Future<void> close() => _database.close();

  @override
  Future<LocalActorIdentity?> getLocal() => _database.transaction((tx) {
    final row = tx.queryRow(
      'SELECT public_key FROM sync_local_actor_identity WHERE id = 1;',
    );
    if (row == null) return null;
    return LocalActorIdentity(
      publicKey: PublicKey(row.field<Uint8List>('public_key')),
    );
  });

  @override
  Future<LocalActorIdentity> setLocal(LocalActorIdentity identity) =>
      _database.transaction((tx) {
        tx.execute(
          '''INSERT INTO sync_local_actor_identity(id, public_key)
          VALUES (1, ?)
          ON CONFLICT(id) DO UPDATE SET public_key = excluded.public_key;''',
          [identity.publicKey.bytes],
        );
        return identity;
      });

  @override
  Future<List<PeerActorIdentity>> allPeers() => _database.transaction((tx) {
    final rows = tx.query(
      'SELECT public_key FROM sync_peer_actor_identity ORDER BY public_key;',
    );
    return [
      for (final row in rows)
        PeerActorIdentity(
          publicKey: PublicKey(row.field<Uint8List>('public_key')),
        ),
    ];
  });

  @override
  Future<void> addPeer(PeerActorIdentity identity) =>
      _database.transaction((tx) {
        tx.execute(
          'INSERT INTO sync_peer_actor_identity(public_key) VALUES (?);',
          [identity.publicKey.bytes],
        );
      });

  @override
  Future<void> deleteAllPeers() => _database.transaction((tx) {
    tx.execute('DELETE FROM sync_peer_actor_identity;');
  });
}
