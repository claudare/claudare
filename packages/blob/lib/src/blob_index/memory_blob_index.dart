import 'blob_index.dart';

/// Indexes blob metadata for the lifetime of this instance.
class MemoryBlobIndex implements BlobIndex {
  final Map<String, BlobStatus> _statuses = {};

  @override
  Future<BlobMetadata> get(String blobId) async => BlobMetadata(
    blobId: blobId,
    status: _statuses[blobId] ?? BlobStatus.missing,
  );

  @override
  Future<void> upsert(BlobMetadata metadata) async {
    _statuses[metadata.blobId] = metadata.status;
  }
}
