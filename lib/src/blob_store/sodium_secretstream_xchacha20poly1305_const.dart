// Tutorial
// https://doc.libsodium.org/doc/secret-key_cryptography/secretstream
// No static defined re-export
class SodiumSecretstreamXChaCha20Poly1305Consts {
  const SodiumSecretstreamXChaCha20Poly1305Consts._();

  static const int keyBytes = 32;
  static const int headerBytes = 24;
  static const int aBytes = 17;

  static int chunkPlaintextSize(int chunkSize) {
    return chunkSize - aBytes;
  }
}
