import 'package:core/src/blob_store/sodium_secretstream_xchacha20poly1305_const.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

void main() {
  group("libsodium consts", () {
    test("secretstream", () async {
      final sodium = await SodiumInit.init();

      expect(
        sodium.crypto.secretStream.keyBytes,
        SodiumSecretstreamXChaCha20Poly1305Consts.keyBytes,
        reason: 'keyBytes mismatch',
      );
      expect(
        sodium.crypto.secretStream.headerBytes,
        SodiumSecretstreamXChaCha20Poly1305Consts.headerBytes,
        reason: 'headerBytes mismatch',
      );
      expect(
        sodium.crypto.secretStream.aBytes,
        SodiumSecretstreamXChaCha20Poly1305Consts.aBytes,
        reason: 'aBytes mismatch',
      );

      final id = sodium.randombytes.buf(16);

      //
    });
  });
}
