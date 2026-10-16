import 'dart:typed_data';

/// Sent to save a command and its events atomically while respecting
/// concurrency.
class LocalBlobSave {
  final String actor;
  final DateTime occuredAt;
  final Uint8List data;

  const LocalBlobSave({
    required this.actor,
    required this.occuredAt,
    required this.data,
  });
}
