part of 'blob.dart';

class BlobReady extends BlobEvent {
  static const String kind = 'blobReady';

  final String blobId;

  const BlobReady({required this.blobId});

  @override
  Map<String, dynamic> toJson() => {'blobId': blobId};

  factory BlobReady.fromJson(Map<String, dynamic> json) =>
      BlobReady(blobId: json['blobId'] as String);
}
