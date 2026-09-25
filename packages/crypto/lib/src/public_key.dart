import 'dart:math';
import 'dart:typed_data';
import 'package:base58/base58.dart';

const publicKeyLength = 32;

/// A public key of 256 bits.
/// Encoded length is 44 bytes in Base58 encoding.
class PublicKey {
  final Uint8List bytes;

  PublicKey(this.bytes) {
    if (bytes.length != publicKeyLength) {
      throw ArgumentError('PublicKey must be $publicKeyLength bytes');
    }
  }

  factory PublicKey.secureRandom() {
    final random = Random.secure();
    final bytes = Uint8List(publicKeyLength);

    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return PublicKey(bytes);
  }

  factory PublicKey.staticValue(int value) {
    final bytes = Uint8List(publicKeyLength);
    // Big-endian bytes make lexicographic ordering match numeric ordering.
    for (var i = bytes.length - 1; i >= 0; i--) {
      bytes[i] = value & 0xff;
      value >>= 8;
    }
    return PublicKey(bytes);
  }

  @override
  toString() => base58Encode(bytes);

  PublicKey.fromString(String str) : bytes = base58Decode(str);
}
