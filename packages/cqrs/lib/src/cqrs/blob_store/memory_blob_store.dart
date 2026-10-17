import 'dart:typed_data';

import 'package:cqrs/src/cqrs/blob_store/blob_store.dart';

/// Stores immutable blobs for the lifetime of this instance.
class MemoryBlobStore implements BlobStore {
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<Uint8List?> get(String blobId) async {
    final data = _blobs[blobId];
    return data == null ? null : Uint8List.fromList(data);
  }

  @override
  Future<void> save(String blobId, Uint8List data) async {
    final existing = _blobs[blobId];
    if (existing != null) {
      if (existing.length != data.length) {
        throw StateError('Blob already contains different bytes: $blobId');
      }
      for (var index = 0; index < data.length; index++) {
        if (existing[index] != data[index]) {
          throw StateError('Blob already contains different bytes: $blobId');
        }
      }
      return;
    }
    _blobs[blobId] = Uint8List.fromList(data);
  }
}
