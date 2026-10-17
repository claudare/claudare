import 'dart:typed_data';

/// Stores immutable binary values by string blob ID.
abstract interface class BlobStore {
  /// Returns complete blob bytes, or null when absent.
  Future<Uint8List?> get(String blobId);

  /// Saves complete bytes durably before returning.
  /// Repeating an identical save succeeds; different bytes for an existing ID
  /// throw [StateError].
  Future<void> save(String blobId, Uint8List data);
}
