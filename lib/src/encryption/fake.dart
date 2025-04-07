import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:async/async.dart';
import 'package:convert/convert.dart';
import 'package:core/core.dart';

import 'package:core/src/encryption/common.dart';

/// fake encryption key, becomes 24 characters after "encrpytion"
class EncryptionKeyFake {
  final Uint8List bytes;

  EncryptionKeyFake(this.bytes) {
    if (bytes.length != 24) {
      throw ArgumentError('Fakecryption must be 18-bytes');
    }
  }

  Encryptor get encryptor => EncryptorFake(this);

  EncryptionKeyFake.notSoRandom(DeviceId deviceId, {Timestamp? timestamp})
    : bytes = Uint8List(24) {
    final deviceStr = deviceId.toString();
    assert(deviceStr.length == 3);

    for (var i = 0; i < 3; i++) {
      bytes[i] = deviceStr.codeUnitAt(i);
    }

    bytes[4] = '_'.codeUnitAt(0);

    final valueReal = timestamp ?? Timestamp.now();
    final valueStr = valueReal.toString();

    assert(valueStr.length == 11);

    for (var i = 0; i < valueStr.length; i++) {
      bytes[5 + i] = valueStr.codeUnitAt(i);
    }
  }

  String toHex() {
    return hex.encode(bytes);
  }

  factory EncryptionKeyFake.fromHex(String hexString) {
    final bytes = Uint8List.fromList(hex.decode(hexString));
    return EncryptionKeyFake(bytes);
  }

  static bool areTheSame(Uint8List bytes1, Uint8List bytes2) {
    if (bytes1.lengthInBytes != bytes2.lengthInBytes) {
      return false;
    }

    for (int i = 0; i < bytes1.length; i++) {
      if (bytes1[i] != bytes2[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() {
    return 'FakecryptionKey{bytes: ${bytes.toString()}}';
  }
}

/// Fake encryption algorithm. Uses base64 and cleartext keys to make sure
/// that the key can decrypt the payload.
class EncryptorFake implements Encryptor {
  static const int chunkSize = 24 * 4; // Process 96 bytes at a time

  final EncryptionKeyFake key;

  EncryptorFake(this.key);

  @override
  Stream<List<int>> encrypt(Stream<List<int>> inputStream) async* {
    final reader = ChunkedStreamReader(inputStream);
    final encoder = Base64Encoder();

    // emit the fakecryption key
    yield key.bytes;

    while (true) {
      final blockList = await reader.readChunk(chunkSize);
      if (blockList.isEmpty) {
        return;
      }

      final isLast = blockList.length < chunkSize;
      final block = Uint8List.fromList(blockList);

      // std hides the actual low level operations
      final result = encoder.convert(block).codeUnits;

      yield result;

      if (isLast) {
        return;
      }
    }
  }

  @override
  Stream<List<int>> decrypt(Stream<List<int>> inputStream) async* {
    final reader = ChunkedStreamReader(inputStream);
    final decoder = Base64Decoder();

    final embeddedKey = Uint8List.fromList(await reader.readChunk(24));

    if (!EncryptionKeyFake.areTheSame(key.bytes, embeddedKey)) {
      throw Exception('Cannot fakedecrypt as keys dont match.');
    }

    while (true) {
      final blockList = await reader.readChunk(chunkSize);
      if (blockList.isEmpty) {
        return;
      }

      final isLast = blockList.length < chunkSize;
      final blockString = String.fromCharCodes(blockList);

      // std hides the actual low level operations
      final out = decoder.convert(blockString);

      yield out;

      if (isLast) {
        return;
      }
    }
  }
}
