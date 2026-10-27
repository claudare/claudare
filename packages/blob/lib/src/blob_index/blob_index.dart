/// Local availability of a blob.
enum BlobStatus {
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

  /// Marks the blob available by its ID. Multiple calls with the same blobId succeed.
  Future<void> markAvailable(String blobId);
}
