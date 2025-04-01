import 'package:core/src/base58.dart';
import 'package:core/src/random.dart';

/// Each blob is identified by a random value endoded with Base58
/// no need to use hashes, random values are enough
class BlobId {
  static const _strLength = 11;

  final String value;

  BlobId(this.value);

  factory BlobId.random() {
    // u64 size        2^64 = 1.84E19
    // 11 char base58 58^11 = 2.49E19

    final intValue = randomU64();
    final strValue = Base58.toStringPadded(intValue, _strLength);

    return BlobId(strValue);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BlobId) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}
