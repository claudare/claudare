import 'dart:convert';
import 'dart:typed_data';

/// A request or response exchanged within one blob replication session.
sealed class BlobReplicationMessage {
  final String blobId;

  const BlobReplicationMessage({required this.blobId});

  Map<String, dynamic> toJson() => switch (this) {
    BlobReplicationMessageRequest() => {'type': 'request', 'blobId': blobId},
    BlobReplicationMessageData(:final bytes) => {
      'type': 'data',
      'blobId': blobId,
      'bytes': base64Encode(bytes),
    },
    BlobReplicationMessageMissing() => {'type': 'missing', 'blobId': blobId},
  };

  /// Rejects malformed messages and invalid base64 with [FormatException].
  factory BlobReplicationMessage.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['blobId'] is! String) {
      throw const FormatException('Blob message requires a string blobId');
    }
    final blobId = value['blobId'] as String;
    return switch (value['type']) {
      'request' => BlobReplicationMessageRequest(blobId: blobId),
      'data' when value['bytes'] is String => BlobReplicationMessageData(
        blobId: blobId,
        bytes: base64Decode(value['bytes'] as String),
      ),
      'missing' => BlobReplicationMessageMissing(blobId: blobId),
      _ => throw const FormatException('Invalid blob message fields'),
    };
  }
}

/// Requests complete bytes for [blobId].
class BlobReplicationMessageRequest extends BlobReplicationMessage {
  const BlobReplicationMessageRequest({required super.blobId});
}

/// Carries complete, immutable bytes for [blobId].
class BlobReplicationMessageData extends BlobReplicationMessage {
  final Uint8List bytes;

  BlobReplicationMessageData({required super.blobId, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
}

/// Reports that the requested [blobId] is absent from the peer.
class BlobReplicationMessageMissing extends BlobReplicationMessage {
  const BlobReplicationMessageMissing({required super.blobId});
}
