import 'dart:typed_data';

/// Stores immutable binary values by string blob ID.
abstract interface class BlobStorage {
  /// Returns complete blob bytes, or null when absent.
  Future<Uint8List?> get(String blobId);

  /// Saves complete bytes durably before returning.
  ///
  /// Repeating an identical save succeeds. Saving different bytes for an
  /// existing ID throws [StateError].
  Future<void> save(String blobId, Uint8List data);
}
