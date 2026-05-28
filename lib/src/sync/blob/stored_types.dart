import 'dart:typed_data';

class StoredBlob {
  final String tenantId; // weak way to check ownership

  final int appId;
  final int deviceId;
  final int sequence;
  final int
  ciphertextLength; // rounded up, minimal value of 2-4kb? Larger blobs are added random amount?
  final int timestamp; // unix seconds
  final Uint8List ciphertext;

  const StoredBlob({
    required this.appId,
    required this.deviceId,
    required this.sequence,
    required this.ciphertextLength,
    required this.timestamp,
    required this.ciphertext,
    required this.tenantId,
  });

  /// the universal id as far as the user is concerned
  /// however, each server is multi-tennant
  String get idAsTheOwner => "$appId/$deviceId/$sequence";
}
