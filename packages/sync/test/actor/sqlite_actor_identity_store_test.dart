import 'dart:io';

import 'package:claudare_crypto/crypto.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  group('SQLite actor identity store', () {
    late SqliteActorIdentityStore store;

    setUp(() async {
      store = await SyncTestHelper.createMemoryActorIdentityStore();
    });
    tearDown(() => store.close());

    test('local identity is absent in a fresh database', () async {
      expect(await store.getLocal(), isNull);
    });

    test('sets and returns the local identity', () async {
      final identity = LocalActorIdentity(publicKey: PublicKey.staticValue(1));

      final saved = await store.setLocal(identity);

      expect(saved.publicKey, identity.publicKey);
      expect((await store.getLocal())!.publicKey, identity.publicKey);
    });

    test('replaces the local identity', () async {
      await store.setLocal(
        LocalActorIdentity(publicKey: PublicKey.staticValue(1)),
      );
      final replacement = LocalActorIdentity(
        publicKey: PublicKey.staticValue(2),
      );

      await store.setLocal(replacement);

      expect((await store.getLocal())!.publicKey, replacement.publicKey);
    });

    test('peers are absent in a fresh database', () async {
      expect(await store.allPeers(), isEmpty);
    });

    test('lists all added peers', () async {
      final keys = [PublicKey.staticValue(2), PublicKey.staticValue(1)];
      for (final key in keys) {
        await store.addPeer(PeerActorIdentity(publicKey: key));
      }

      expect(
        (await store.allPeers()).map((peer) => peer.publicKey),
        unorderedEquals(keys),
      );
    });

    test('rejects a duplicate peer by public key value', () async {
      final key = PublicKey.staticValue(1);
      await store.addPeer(PeerActorIdentity(publicKey: key));
      final duplicate = PeerActorIdentity(
        publicKey: PublicKey.fromString(key.toString()),
      );

      await expectLater(store.addPeer(duplicate), throwsException);

      expect((await store.allPeers()).map((peer) => peer.publicKey), [key]);
    });

    test('gets a peer by public key value', () async {
      final key = PublicKey.staticValue(1);
      for (final value in [1, 2]) {
        await store.addPeer(
          PeerActorIdentity(publicKey: PublicKey.staticValue(value)),
        );
      }

      final peer = await store.getPeer(PublicKey.fromString(key.toString()));

      expect(peer?.publicKey, key);
    });

    test('returns null for an unknown peer', () async {
      await store.addPeer(
        PeerActorIdentity(publicKey: PublicKey.staticValue(1)),
      );

      expect(await store.getPeer(PublicKey.staticValue(2)), isNull);
    });

    test('returns null for a removed peer', () async {
      final key = PublicKey.staticValue(1);
      await store.addPeer(PeerActorIdentity(publicKey: key));
      await store.deleteAllPeers();

      expect(await store.getPeer(key), isNull);
    });

    test('deletes only the peer with the given public key value', () async {
      final key = PublicKey.staticValue(1);
      final remainingKey = PublicKey.staticValue(2);
      for (final peerKey in [key, remainingKey]) {
        await store.addPeer(PeerActorIdentity(publicKey: peerKey));
      }

      await store.deletePeer(PublicKey.fromString(key.toString()));

      expect(await store.getPeer(key), isNull);
      expect((await store.allPeers()).map((peer) => peer.publicKey), [
        remainingKey,
      ]);
    });

    test('deleting one peer preserves the local identity', () async {
      final key = PublicKey.staticValue(1);
      await store.setLocal(LocalActorIdentity(publicKey: key));
      await store.addPeer(PeerActorIdentity(publicKey: key));

      await store.deletePeer(key);

      expect((await store.getLocal())!.publicKey, key);
    });

    test('deleting an unknown peer preserves existing peers', () async {
      final key = PublicKey.staticValue(1);
      await store.addPeer(PeerActorIdentity(publicKey: key));

      await store.deletePeer(PublicKey.staticValue(2));

      expect((await store.allPeers()).map((peer) => peer.publicKey), [key]);
    });

    test('a deleted peer can be added again', () async {
      final identity = PeerActorIdentity(publicKey: PublicKey.staticValue(1));
      await store.addPeer(identity);
      await store.deletePeer(identity.publicKey);

      await store.addPeer(identity);

      expect(
        (await store.getPeer(identity.publicKey))?.publicKey,
        identity.publicKey,
      );
    });

    test('deletes all peers', () async {
      for (final value in [1, 2]) {
        await store.addPeer(
          PeerActorIdentity(publicKey: PublicKey.staticValue(value)),
        );
      }

      await store.deleteAllPeers();

      expect(await store.allPeers(), isEmpty);
    });

    test('deleting peers preserves the local identity', () async {
      final key = PublicKey.staticValue(1);
      await store.setLocal(LocalActorIdentity(publicKey: key));
      await store.addPeer(
        PeerActorIdentity(publicKey: PublicKey.staticValue(2)),
      );

      await store.deleteAllPeers();

      expect((await store.getLocal())!.publicKey, key);
    });

    test('deleting peers from an empty store succeeds', () async {
      await store.deleteAllPeers();

      expect(await store.allPeers(), isEmpty);
    });

    test('repeated migration preserves identities', () async {
      final localKey = PublicKey.staticValue(1);
      final peerKey = PublicKey.staticValue(2);
      await store.setLocal(LocalActorIdentity(publicKey: localKey));
      await store.addPeer(PeerActorIdentity(publicKey: peerKey));

      await store.migrate();

      expect((await store.getLocal())!.publicKey, localKey);
      expect((await store.allPeers()).map((peer) => peer.publicKey), [peerKey]);
    });
  });

  test('identities persist across database reopen', () async {
    final directory = await Directory.systemTemp.createTemp('sync-identity-');
    addTearDown(() => directory.delete(recursive: true));
    final filename = '${directory.path}/identities.sqlite';
    final database = IsolateSqlite();
    await database.open(filename);
    final store = SqliteActorIdentityStore(database);
    final localKey = PublicKey.staticValue(1);
    final peerKey = PublicKey.staticValue(2);
    final deletedKey = PublicKey.staticValue(3);
    try {
      await store.migrate();
      await store.setLocal(LocalActorIdentity(publicKey: localKey));
      await store.addPeer(PeerActorIdentity(publicKey: peerKey));
      await store.addPeer(PeerActorIdentity(publicKey: deletedKey));
      await store.deletePeer(deletedKey);
    } finally {
      await store.close();
    }

    final reopenedDatabase = IsolateSqlite();
    await reopenedDatabase.open(filename);
    final reopened = SqliteActorIdentityStore(reopenedDatabase);
    addTearDown(reopened.close);
    await reopened.migrate();

    expect((await reopened.getLocal())!.publicKey, localKey);
    expect(await reopened.getPeer(deletedKey), isNull);
    expect((await reopened.allPeers()).map((peer) => peer.publicKey), [
      peerKey,
    ]);
  });
}
