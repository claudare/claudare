import 'package:claudare_crypto/crypto.dart';
import 'package:sync/src/actor/actor_identity_store.dart';

class SqliteActorIdentityStore implements ActorIdentityStore {
  @override
  Future<LocalActorIdentity?> getLocal() {
    // TODO: implement getLocal
    throw UnimplementedError();
  }

  @override
  Future<LocalActorIdentity> setLocal(LocalActorIdentity identity) {
    // TODO: implement setLocal
    throw UnimplementedError();
  }

  @override
  Future<List<PeerActorIdentity>> allPeers() {
    // TODO: implement allPeers
    throw UnimplementedError();
  }

  @override
  Future<void> addPeer(PeerActorIdentity identity) {
    // TODO: implement addPeer
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAllPeers() {
    // TODO: implement deleteAllPeers
    throw UnimplementedError();
  }
}
