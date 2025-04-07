import 'package:core/src/encryption/scheme.dart';

/// [BlobMetadata] is for the client side only,
/// Its stored in the system's event store
/// Holds needed context for the application, when it needs to read this
/// Each blob has its own encryption key.
class BlobMetadata {
  final EncryptionAnyScheme encryptionScheme;
  final int plaintextLengthBytes; // for UI
  final String mimeType; // for internal app functinality

  const BlobMetadata(
    this.encryptionScheme,
    this.plaintextLengthBytes,
    this.mimeType,
  );

  BlobMetadata.fromJson(Map<String, dynamic> json)
    : encryptionScheme = EncryptionAnyScheme.fromJson(json['encryptionScheme']),
      plaintextLengthBytes = json['plaintextSizeBytes'],
      mimeType = json['mimeType'];

  Map<String, dynamic> toJson() => {
    'encryptionScheme': encryptionScheme.toJson(),
    'plaintextSizeBytes': plaintextLengthBytes,
    'mimeType': mimeType,
  };
}
