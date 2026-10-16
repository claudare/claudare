import 'dart:typed_data';

import 'package:cqrs/src/cqrs/blob_store/blob_id.dart';

class StoredBlob {
  final BlobId blobId;
  final Uint8List data;
  final DateTime createdAt;

  const StoredBlob({
    required this.blobId,
    required this.data,
    required this.createdAt,
  });
}
