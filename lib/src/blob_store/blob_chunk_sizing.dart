// A helper class to do chunk-level (fixed size block) encryption of data.
// The ciphertext payload length must be fixed between 4KB and 1MB,
// using an exponent as indicator of size.
// Since encrypted ciphertext contains a tag of arbitrary fixed length, the chunk
// cleartext capacity is slightly less.
// The chunks must strictly align with the chunk size (block size). Any
// empty data is filled with padding.
// Zero length payloads are allowed. They will be filled with padding
class BlobChunkSizing {
  /// Minimum exponent. 2^12 = 4,096 bytes (4 KB).
  static const int minExponent = 12;
  static const int minSizeBytes = 1 << minExponent;

  /// Maximum exponent. 2^20 = 1,048,576 bytes (1 MB).
  static const int maxExponent = 20;
  static const int maxSizeBytes = 1 << maxExponent;

  final int _chunkCount;
  final int _exponent;
  final int _chunkOverhead;
  final int _cleartextByteLen;

  // this is _exponentToByteLen(_exponent), calculated during initialization for performance
  late final int _ciphertextChunkLen = _exponentToByteLen(_exponent);

  BlobChunkSizing._(
    this._chunkCount,
    this._exponent,
    this._chunkOverhead,
    this._cleartextByteLen,
  );

  /// Creates chunk sizing from the cleartext length and per-chunk overhead.
  factory BlobChunkSizing.fromCleartextLen(
    int cleartextByteLen,
    int chunkOverheadByteLen,
  ) {
    if (cleartextByteLen < 0) {
      throw ArgumentError.value(
        cleartextByteLen,
        'cleartextByteLen',
        'must be non-negative',
      );
    }
    if (chunkOverheadByteLen < 0) {
      throw ArgumentError.value(
        chunkOverheadByteLen,
        'chunkOverheadByteLen',
        'must be non-negative',
      );
    }

    // Choose the smallest ciphertext chunk size (2^exp) such that
    // at least one chunk can hold data after overhead.
    final minCiphertextNeeded = chunkOverheadByteLen + 1;
    final exponent = _exponentFromByteLen(minCiphertextNeeded);
    final ciphertextChunkLen = _exponentToByteLen(exponent);
    final cleartextChunkLen = ciphertextChunkLen - chunkOverheadByteLen;

    final chunkCount =
        cleartextByteLen == 0
            ? 0
            : ((cleartextByteLen + cleartextChunkLen - 1) ~/ cleartextChunkLen);

    return BlobChunkSizing._(
      chunkCount,
      exponent,
      chunkOverheadByteLen,
      cleartextByteLen,
    );
  }

  /// Creates chunk sizing from the exponent (stored in DB) and overhead.
  ///
  /// `_chunkCount` and end padding depend on actual cleartext length and are
  /// therefore initialized to 0 here.
  factory BlobChunkSizing.fromExponent(int exponent, int chunkOverheadByteLen) {
    if (exponent < minExponent || exponent > maxExponent) {
      throw ArgumentError.value(
        exponent,
        'exponent',
        'out of range [$minExponent..$maxExponent]',
      );
    }
    if (chunkOverheadByteLen < 0) {
      throw ArgumentError.value(
        chunkOverheadByteLen,
        'chunkOverheadByteLen',
        'must be non-negative',
      );
    }

    final ciphertextChunkLen = _exponentToByteLen(exponent);
    if (chunkOverheadByteLen >= ciphertextChunkLen) {
      throw ArgumentError.value(
        chunkOverheadByteLen,
        'chunkOverheadByteLen',
        'must be smaller than ciphertext chunk length ($ciphertextChunkLen)',
      );
    }

    return BlobChunkSizing._(0, exponent, chunkOverheadByteLen, 0);
  }

  int get chunkCount => _chunkCount;
  int get exponent => _exponent;
  int get chunkOverhead => _chunkOverhead;
  int get cleartextChunkLen => _ciphertextChunkLen - _chunkOverhead;
  int get ciphertextChunkLen => _ciphertextChunkLen;

  /// Padding bytes in the final cleartext chunk.
  int get endPaddingLen {
    if (_chunkCount == 0) return 0;
    final usedInLastChunk = _cleartextByteLen % cleartextChunkLen;
    return usedInLastChunk == 0 ? 0 : (cleartextChunkLen - usedInLastChunk);
  }

  /// Converts exponent [n] to its byte count: 2^n.
  static int _exponentToByteLen(int exponent) {
    assert(
      exponent >= minExponent && exponent <= maxExponent,
      'exponent $exponent out of range [$minExponent..$maxExponent]',
    );
    return 1 << exponent;
  }

  static int _exponentFromByteLen(int byteLength) {
    if (byteLength < 0) {
      throw ArgumentError.value(
        byteLength,
        'byteLength',
        'must be non-negative',
      );
    }
    if (byteLength <= (1 << minExponent)) return minExponent;
    final target = byteLength;
    return _ceilLog2(target).clamp(minExponent, maxExponent);
  }

  /// Smallest [n] such that 2^n >= [value].
  static int _ceilLog2(int value) {
    assert(value > 0);
    int exp = 0;
    int p = 1;
    while (p < value) {
      p <<= 1;
      exp++;
    }
    return exp;
  }
}
