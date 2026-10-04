import 'package:claudare_crypto/crypto.dart';
import 'package:sync/src/actor/actor_identity_store.dart';

/// Stores local and peer identities in memory for this instance.
class MemoryActorIdentityStore implements ActorIdentityStore {
  LocalActorIdentity? _local;
  final _peers = <PublicKey, PeerActorIdentity>{};

  @override
  Future<LocalActorIdentity?> getLocal() async => _local;

  @override
  Future<LocalActorIdentity> setLocal(LocalActorIdentity identity) async =>
      _local = identity;

  @override
  Future<List<PeerActorIdentity>> allPeers() async =>
      _peers.values.toList()
        ..sort((a, b) => a.publicKey.compareTo(b.publicKey));

  @override
  Future<PeerActorIdentity?> getPeer(PublicKey publicKey) async =>
      _peers[publicKey];

  @override
  Future<void> addPeer(PeerActorIdentity identity) async {
    if (_peers.containsKey(identity.publicKey)) {
      throw Exception('Peer identity already exists');
    }
    _peers[identity.publicKey] = identity;
  }

  @override
  Future<void> deletePeer(PublicKey publicKey) async {
    _peers.remove(publicKey);
  }

  @override
  Future<void> deleteAllPeers() async => _peers.clear();
}
