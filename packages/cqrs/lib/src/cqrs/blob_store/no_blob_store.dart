import 'dart:typed_data';

import 'package:cqrs/src/cqrs/blob_store/blob_store.dart';

/// Disables blob storage by rejecting all reads and writes.
class NoBlobStore implements BlobStore {
  const NoBlobStore();

  /// Throws [UnsupportedError] because blob storage is disabled.
  @override
  Future<Uint8List?> get(String blobId) =>
      throw UnsupportedError('Blob storage is disabled');

  /// Throws [UnsupportedError] because blob storage is disabled.
  @override
  Future<void> save(String blobId, Uint8List data) =>
      throw UnsupportedError('Blob storage is disabled');
}
