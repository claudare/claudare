import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:async/async.dart';

import 'package:core/src/encryption/common.dart';

/// base64 will be used for testing. At first its okay to pretend like things
/// are encrypted
class EncryptorBase64 implements Encryptor {
  static const int chunkSize = 24 * 4; // Process 96 bytes at a time

  @override
  Stream<List<int>> encrypt(Stream<List<int>> inputStream) async* {
    final reader = ChunkedStreamReader(inputStream);
    final encoder = Base64Encoder();

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
