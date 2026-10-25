import 'package:claudare_crypto/crypto.dart';
import 'package:identity/src/pairing/pairing_message.dart';

/// [PairingBootstrap] is the information needed to start the pairing procedure.
/// This information is contained inside the QR code. The token must be acked
/// For pairing to succeed. Token does not provide any security but rather tells
/// who is pairing. This is a standalone message.
class PairingBootstrap {
  /// Public key of the requester (QR generator)
  final PublicKey publicKey;
  final String serverUrl;
  final String group;
  final String token;

  const PairingBootstrap({
    required this.publicKey,
    required this.serverUrl,
    required this.group,
    required this.token,
  });
}
