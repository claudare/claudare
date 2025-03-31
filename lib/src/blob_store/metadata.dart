import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Metadata for the client side
/// Stored as the first part of the blob, encrypted with the rest of the data
/// this is immutable and will never change
class BlobMetadata {
  final int plaintextLengthBytes;
  final String mimeType;

  // this could also hold arbitrary key value pairs
  // or that is left upto the application to contruct own metadatas there
  // final List<{Key, Value}> extra;

  const BlobMetadata(this.plaintextLengthBytes, this.mimeType);

  factory BlobMetadata.fromJson(Map<String, dynamic> json) {
    return BlobMetadata(json['plaintextSizeBytes'], json['mimeType']);
  }

  Map<String, dynamic> toJson() => {
    'plaintextSizeBytes': plaintextLengthBytes,
    'mimeType': mimeType,
  };
}
