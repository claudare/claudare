import 'package:claudare_crypto/crypto.dart';

class LocalActorIdentity {
  /// [PublicKey] is our public key. For the current prototype, there is no
  /// private keys. There is no verification or encryption.
  final PublicKey publicKey;

  const LocalActorIdentity({required this.publicKey});
}

class PeerActorIdentity {
  /// [PublicKey] is the peer device identity.
  /// For now there is no verification or encryption. However, it will be an
  /// actual cryptographic public key.
  final PublicKey publicKey;

  const PeerActorIdentity({required this.publicKey});
}

/// A centralized place to store local and remote peers identities.
abstract interface class ActorIdentityStore {
  /// Gets own Identity
  Future<LocalActorIdentity?> getLocal();

  /// Sets own Identity
  Future<LocalActorIdentity> setLocal(LocalActorIdentity identity);

  /// Get a list of all peer identities.
  Future<List<PeerActorIdentity>> allPeers();

  /// Adds a peer to the identity store. Double addition is not allowed.
  /// Throws when peer with the given identity already exists.
  Future<void> addPeer(PeerActorIdentity identity);

  /// Delete all peers from the store.
  /// This function is convenient in dev environment.
  Future<void> deleteAllPeers();
}
