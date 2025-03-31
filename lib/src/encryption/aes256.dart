import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:pointycastle/export.dart';
import 'package:core/src/encryption/common.dart';

class AES256Key {
  final Uint8List bytes;

  AES256Key(this.bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('AES-256 requires a 32-byte key');
    }
  }
  factory AES256Key.secureRandom() {
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }

    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(seed));

    final bytes = secureRandom.nextBytes(32);
    return AES256Key(bytes);
  }
}

/// WARNING: I have no idea what I am doing.
/// the encrpyion choices and implementation is entirely AI generated
/// do not use until its validated to be correct!
class AES256Encryption implements Encryption {
  final AES256Key key;
  static const int ivLength = 16; // AES block size

  /// Creates an AES-256 encryption instance with the given 32-byte key
  AES256Encryption(this.key);

  /// Generate secure random IV
  Uint8List _generateIV() {
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = random.nextInt(256);
    }

    final secureRandom = FortunaRandom();
    secureRandom.seed(KeyParameter(seed));

    return secureRandom.nextBytes(ivLength);
  }

  // Helper method to create CBC cipher
  BlockCipher _createCipher(bool forEncryption, Uint8List iv) {
    final cipher = CBCBlockCipher(AESEngine());
    final params = ParametersWithIV<KeyParameter>(KeyParameter(key.bytes), iv);
    cipher.init(forEncryption, params);
    return cipher;
  }

  // Helper method to apply padding
  Uint8List _pad(Uint8List data) {
    final padder = PKCS7Padding();
    final paddedLength = (data.length ~/ 16 + 1) * 16;
    final paddedData = Uint8List(paddedLength);
    paddedData.setAll(0, data);
    padder.addPadding(paddedData, data.length);
    return paddedData;
  }

  // Helper method to remove padding
  // this does not work, as it throws if last block has no padding...
  Uint8List _unpad(Uint8List data) {
    final padder = PKCS7Padding();
    final paddingLength = padder.padCount(data);
    return data.sublist(0, data.length - paddingLength);
  }

  Uint8List _maybeUnpad(Uint8List data) {
    try {
      return _unpad(data);
    } catch (e) {
      return data;
    }
  }

  @override
  Stream<List<int>> encrypt(Stream<List<int>> inputStream) async* {
    // Generate a random IV
    final iv = _generateIV();

    // First yield the IV
    yield iv;

    final cipher = _createCipher(true, iv);

    final reader = ChunkedStreamReader(inputStream);

    while (true) {
      final blockList = await reader.readChunk(16);
      if (blockList.isEmpty) {
        return;
      }

      final isLast = blockList.length < 16;
      final block =
          isLast
              ? _pad(Uint8List.fromList(blockList))
              : Uint8List.fromList(blockList);

      final encrypted = Uint8List(16);
      cipher.processBlock(block, 0, encrypted, 0);
      yield encrypted;

      if (isLast) {
        return;
      }
    }
  }

  @override
  Stream<List<int>> decrypt(Stream<List<int>> inputStream) async* {
    Uint8List? iv;
    late BlockCipher cipher;

    final reader = ChunkedStreamReader(inputStream);

    bool outSet = false;

    final out = Uint8List(16);
    while (true) {
      final blockList = await reader.readChunk(16);
      if (outSet) {
        if (blockList.isEmpty) {
          yield _maybeUnpad(out);
          return;
        } else {
          yield out;
        }
      }

      final block = Uint8List.fromList(blockList);
      if (iv == null) {
        iv = block;
        cipher = _createCipher(false, iv);
        continue;
      }

      cipher.processBlock(block, 0, out, 0);
      outSet = true;
    }
  }
}
