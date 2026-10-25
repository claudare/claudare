import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_crypto/crypto.dart';

/// A request or response exchanged within one pairing session.
sealed class PairingMessage {
  const PairingMessage();

  Map<String, dynamic> toJson() => switch (this) {
    PairingMessageBootstrapAccept() => {'type': 'request'},
    PairingMessageKnownPeers() => throw UnimplementedError(),
  };

  /// Rejects malformed messages and invalid base64 with [FormatException].
  factory PairingMessage.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['blobId'] is! String) {
      throw const FormatException('Blob message requires a string blobId');
    }
    final blobId = value['blobId'] as String;
    return switch (value['type']) {
      'bootstrap_accept' => PairingMessageBootstrapAccept(
        publicKey: PublicKey.fromString(value['publicKey']),
        token: value['token'],
      ),
      'known_peers' => throw UnimplementedError(),
      _ => throw const FormatException('Invalid blob message fields'),
    };
  }
}

/// [PairingMessageBootstrapAccept] is the reply to the [PairingBootstrap].
/// This is the first message in the protocol when pairing. Same token is
/// replied with.
/// When already paired, this message is skipped?
class PairingMessageBootstrapAccept extends PairingMessage {
  /// Public key of the accepter (QR scanner)
  final PublicKey publicKey;
  final String token;

  const PairingMessageBootstrapAccept({
    required this.publicKey,
    required this.token,
  });
}

class KnownPeer {
  final PublicKey publicKey;

  /// names cannot be changed
  final String name;

  /// Once peer is removed they can never join again. Create a new identity.
  final bool isRemoved;

  const KnownPeer({
    required this.publicKey,
    required this.name,
    required this.isRemoved,
  });
}

/// [PairingMessageKnownPeers] tells the other peer all of the peers we know.
/// This includes the sender as well.
/// The known peers are currently modeled as the crdt set, where removals are
/// permanent.
/// The renames also cannot be changed...
class PairingMessageKnownPeers extends PairingMessage {
  final List<KnownPeer> peers;

  const PairingMessageKnownPeers({required this.peers});
}
