/// Local availability of a blob.
enum BlobStatus {
  /// The blob is known, but is not available locally yet.
  pending,

  /// The complete blob bytes are available locally.
  available,

  /// The blob is not known locally.
  missing,
}

/// The locally known metadata for a blob.
final class BlobMetadata {
  final String blobId;
  final BlobStatus status;

  const BlobMetadata({required this.blobId, required this.status});
}

/// Indexes locally known blob metadata by blob ID.
abstract interface class BlobIndex {
  /// Returns metadata for [blobId].
  ///
  /// Unknown IDs return metadata with [BlobStatus.missing].
  Future<BlobMetadata> get(String blobId);

  /// Adds or replaces metadata for its blob ID.
  Future<void> upsert(BlobMetadata metadata);
}
