/// Each blob is identified by a random value endoded with Base58
/// no need to use hashes, random values are enough
class BlobId {
  final String value;

  BlobId(this.value);
}
