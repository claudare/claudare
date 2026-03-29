import 'package:core/src/blob_store/blob_chunk_sizing.dart';
import 'package:test/test.dart';

void main() {
  // TODO: test middle grounds... maybe
  group("BlockChunkSizing chunk exponentiation", () {
    test("single chunk below minimum", () {
      final s = BlobChunkSizing.fromCleartextLen(
        BlobChunkSizing.minSizeBytes - 1,
        0,
      );

      expect(s.chunkCount, 1);
      expect(s.exponent, BlobChunkSizing.minExponent);
      expect(s.ciphertextChunkLen, BlobChunkSizing.minSizeBytes);
      expect(s.cleartextChunkLen, BlobChunkSizing.minSizeBytes);
      expect(s.endPaddingLen, 1);
    });
    test("double chunk above maximum", () {
      final s = BlobChunkSizing.fromCleartextLen(
        BlobChunkSizing.maxSizeBytes + 1,
        0,
      );

      expect(s.chunkCount, 2);
      expect(s.exponent, BlobChunkSizing.maxExponent);
      expect(s.cleartextChunkLen, BlobChunkSizing.maxSizeBytes + 1);
      expect(s.ciphertextChunkLen, BlobChunkSizing.maxSizeBytes);
      expect(s.endPaddingLen, BlobChunkSizing.maxSizeBytes - 1);
    });
  });

  group('BlobChunkSizing.fromCleartextLen', () {
    test('zero cleartext => zero chunks and zero padding', () {
      final s = BlobChunkSizing.fromCleartextLen(0, 16);

      expect(s.chunkCount, 0);
      expect(s.endPaddingLen, 0);
      expect(s.chunkOverhead, 16);
      expect(s.cleartextChunkLen, s.ciphertextChunkLen - 16);
    });

    test('exactly one cleartext chunk => one chunk, zero padding', () {
      final s0 = BlobChunkSizing.fromCleartextLen(1, 16);
      final chunkLen = s0.cleartextChunkLen;

      final s = BlobChunkSizing.fromCleartextLen(chunkLen, 16);
      expect(s.chunkCount, 1);
      expect(s.endPaddingLen, 0);
    });

    test('one byte over one chunk => two chunks, chunkLen-1 padding', () {
      final s0 = BlobChunkSizing.fromCleartextLen(1, 16);
      final chunkLen = s0.cleartextChunkLen;

      final s = BlobChunkSizing.fromCleartextLen(chunkLen + 1, 16);
      expect(s.chunkCount, 2);
      expect(s.endPaddingLen, chunkLen - 1);
    });

    test('small overhead picks min exponent (4KB ciphertext chunk)', () {
      final s = BlobChunkSizing.fromCleartextLen(100, 16);
      expect(s.exponent, BlobChunkSizing.minExponent);
      expect(s.ciphertextChunkLen, 1 << BlobChunkSizing.minExponent);
    });

    test('negative cleartext throws', () {
      expect(
        () => BlobChunkSizing.fromCleartextLen(-1, 16),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negative overhead throws', () {
      expect(
        () => BlobChunkSizing.fromCleartextLen(1, -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('BlobChunkSizing.fromExponent', () {
    test('valid exponent initializes chunk lengths', () {
      final s = BlobChunkSizing.fromExponent(12, 16);

      expect(s.exponent, 12);
      expect(s.ciphertextChunkLen, 4096);
      expect(s.cleartextChunkLen, 4096 - 16);
      expect(s.chunkCount, 0); // no cleartext length context
      expect(s.endPaddingLen, 0);
    });

    test('min and max exponent accepted', () {
      expect(
        () => BlobChunkSizing.fromExponent(BlobChunkSizing.minExponent, 1),
        returnsNormally,
      );
      expect(
        () => BlobChunkSizing.fromExponent(BlobChunkSizing.maxExponent, 1),
        returnsNormally,
      );
    });

    test('exponent below min throws', () {
      expect(
        () => BlobChunkSizing.fromExponent(BlobChunkSizing.minExponent - 1, 16),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exponent above max throws', () {
      expect(
        () => BlobChunkSizing.fromExponent(BlobChunkSizing.maxExponent + 1, 16),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('overhead equal to ciphertext chunk len throws', () {
      expect(
        () => BlobChunkSizing.fromExponent(12, 4096),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negative overhead throws', () {
      expect(
        () => BlobChunkSizing.fromExponent(12, -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
