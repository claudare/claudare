part of 'blob.dart';

class BlobTombstoned extends BlobEvent {
  static const String kind = 'blobTombstoned';

  final String blobId;

  const BlobTombstoned({required this.blobId});

  @override
  Map<String, dynamic> toJson() => {'blobId': blobId};

  factory BlobTombstoned.fromJson(Map<String, dynamic> json) =>
      BlobTombstoned(blobId: json['blobId'] as String);
}
