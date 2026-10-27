import 'blob_index.dart';

/// Indexes blob metadata for the lifetime of this instance.
class MemoryBlobIndex implements BlobIndex {
  final Set<String> _blobs = {};

  @override
  Future<BlobMetadata> get(String blobId) async => BlobMetadata(
    blobId: blobId,
    status: _blobs.contains(blobId) ? BlobStatus.available : BlobStatus.missing,
  );

  @override
  Future<void> markAvailable(String blobId) async {
    _blobs.add(blobId);
  }
}
