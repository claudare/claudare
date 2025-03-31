/// [BlobMetadata] is for the client side, stored in the system's event store
/// Holds needed context for the application, when it needs to read this
class BlobMetadata {
  final int plaintextLengthBytes; // for UI
  final String mimeType; // for internal app functinality

  const BlobMetadata(this.plaintextLengthBytes, this.mimeType);

  factory BlobMetadata.fromJson(Map<String, dynamic> json) {
    return BlobMetadata(json['plaintextSizeBytes'], json['mimeType']);
  }

  Map<String, dynamic> toJson() => {
    'plaintextSizeBytes': plaintextLengthBytes,
    'mimeType': mimeType,
  };
}
