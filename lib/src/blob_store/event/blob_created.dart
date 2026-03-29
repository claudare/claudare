part of 'blob.dart';

// version for libsodium
// will have no encryption for version 0?
class BlobCreatedSodiumSecretstream extends BlobEvent {
  static const String kind = 'blobCreated1';

  final String blobId; // 16 bytes UUID
  final Uint8List key;
  final int plaintextSize;
  final int chunkExponent;

  final int createdAt;
  final DeviceId deviceId;
  final String? mimeType;

  const BlobCreatedSodiumSecretstream({
    required this.blobId,
    required this.key,
    required this.plaintextSize,
    required this.chunkExponent,
    required this.createdAt,
    required this.deviceId,
    this.mimeType,
  });

  // unique for all blob created
  BlobChunkSizing get chunkSizing => BlobChunkSizing.fromExponent(
    chunkExponent,
    SodiumSecretstreamXChaCha20Poly1305Consts.aBytes,
  );

  @override
  Map<String, dynamic> toJson() => {
    'blobId': blobId,
    'key': base64Url.encode(key),
    'plaintextSize': plaintextSize,
    'chunkExponent': chunkExponent,
    'createdAt': createdAt,
    'deviceId': deviceId,
    if (mimeType != null) 'mimeType': mimeType,
  };

  factory BlobCreatedSodiumSecretstream.fromJson(Map<String, dynamic> json) =>
      BlobCreatedSodiumSecretstream(
        blobId: json['blobId'] as String,
        key: base64Url.decode(json['key'] as String),
        plaintextSize: json['plaintextSize'] as int,
        chunkExponent: json['chunkExponent'] as int,
        createdAt: json['createdAt'] as int,
        deviceId: DeviceId(json['deviceId'] as int),
        mimeType: json['mimeType'] as String?,
      );
}
