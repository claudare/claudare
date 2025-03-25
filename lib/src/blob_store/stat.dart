import 'package:core/src/timestamp.dart';

/// Additional information stored alongside with the blob.
/// This is avaialble to the server. This can also be cached for larger scale
/// deployments. For now though, FileStat is used instead
class BlobStat {
  /// how big the blob is in bytes
  final int ciphertextLengthBytes;

  /// unix timestamp when the blob was created
  final Timestamp createdAt;

  /// unix timestamp when the blob was last accessed
  final Timestamp lastAccessedAt;

  const BlobStat(
    this.ciphertextLengthBytes,
    this.createdAt,
    this.lastAccessedAt,
  );

  BlobStat.fresh(this.ciphertextLengthBytes, this.createdAt)
    : lastAccessedAt = createdAt;

  // BlobStat.fromJson(Map<String, dynamic> json)
  //   : ciphertextLengthBytes = json['ciphertextSizeBytes'],
  //     createdAt = Timestamp.fromJson(json['createdAt']),
  //     lastAccessedAt = Timestamp.fromJson(json['lastAccessedAt']);

  // Map<String, dynamic> toJson() => {
  //   'ciphertextSizeBytes': ciphertextLengthBytes,
  //   'createdAt': createdAt.toJson(),
  //   'lastAccessedAt': lastAccessedAt.toJson(),
  // };
  @override
  String toString() =>
      'BlobMetadataCleartext{ciphertextSizeBytes: $ciphertextLengthBytes, createdAt: $createdAt, lastAccessedAt: $lastAccessedAt}';
}
