// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import 'blob_index/blob_index.dart';
import 'blob_storage/blob_storage.dart';

/// Reads and saves blobs using an availability index and byte storage.
class BlobStore {
  final BlobIndex _index;
  final BlobStorage _storage;

  const BlobStore({required this._index, required this._storage});

  /// Returns available blob bytes, or null when missing or pending.
  Future<Uint8List?> get(String blobId) async {
    final metadata = await _index.get(blobId);
    if (metadata.status != BlobStatus.available) return null;

    final data = await _storage.get(blobId);
    if (data == null) {
      throw StateError(
        'Blob is indexed as available but missing from storage: $blobId',
      );
    }
    return data;
  }

  /// Saves immutable bytes before marking the blob as available.
  Future<void> save(String blobId, Uint8List data) async {
    await _storage.save(blobId, data);
    await _index.upsert(
      BlobMetadata(blobId: blobId, status: BlobStatus.available),
    );
  }
}
