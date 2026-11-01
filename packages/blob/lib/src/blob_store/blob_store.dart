import 'dart:typed_data';

/// Stores immutable binary values by string blob ID.
abstract interface class BlobStore {
  /// Broadcasts newly available IDs after persistence, without replay.
  /// Identical saves and deletions emit nothing. Observe the shared instance.
  Stream<String> get availableBlobs;

  /// Returns complete blob bytes, or null when absent.
  Future<Uint8List?> get(String blobId);

  /// Saves complete bytes durably before returning.
  ///
  /// Repeating an identical save succeeds. Saving different bytes for an
  /// existing ID throws [StateError].
  Future<void> save(String blobId, Uint8List data);

  /// Returns the IDs of locally stored blobs, in unspecified order.
  Future<List<String>> listIds();

  /// Deletes a blob if it exists.
  Future<void> delete(String blobId);
}
