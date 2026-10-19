import 'dart:convert';
import 'dart:typed_data';

import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  for (final (description, message, json)
      in <(String, BlobReplicationMessage, Map<String, dynamic>)>[
        (
          'request',
          const BlobReplicationMessageRequest(blobId: 'blob'),
          {'type': 'request', 'blobId': 'blob'},
        ),
        (
          'data',
          BlobReplicationMessageData(
            blobId: 'blob',
            bytes: Uint8List.fromList([0, 127, 128, 255]),
          ),
          {'type': 'data', 'blobId': 'blob', 'bytes': 'AH+A/w=='},
        ),
        (
          'empty data',
          BlobReplicationMessageData(blobId: 'blob', bytes: Uint8List(0)),
          {'type': 'data', 'blobId': 'blob', 'bytes': ''},
        ),
        (
          'missing',
          const BlobReplicationMessageMissing(blobId: 'blob'),
          {'type': 'missing', 'blobId': 'blob'},
        ),
      ]) {
    test('$description preserves its fields through a JSON round trip', () {
      expect(message.toJson(), json);
      final decoded = BlobReplicationMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())),
      );
      expect(decoded.runtimeType, message.runtimeType);
      expect(decoded.blobId, message.blobId);
      if (message is BlobReplicationMessageData) {
        expect((decoded as BlobReplicationMessageData).bytes, message.bytes);
      }
    });
  }

  test('data message copies input bytes', () {
    final bytes = Uint8List.fromList([1, 2]);
    final message = BlobReplicationMessageData(blobId: 'blob', bytes: bytes);
    bytes[0] = 3;
    expect(message.bytes, [1, 2]);
  });

  test('data message bytes cannot be modified', () {
    final message = BlobReplicationMessageData(
      blobId: 'blob',
      bytes: Uint8List.fromList([1]),
    );
    expect(() => message.bytes[0] = 2, throwsUnsupportedError);
  });

  for (final (description, json) in <(String, Object?)>[
    ('non-object', []),
    ('unknown type', {'type': 'unknown', 'blobId': 'blob'}),
    ('missing blob ID', {'type': 'request'}),
    ('invalid blob ID', {'type': 'request', 'blobId': 42}),
    ('missing bytes', {'type': 'data', 'blobId': 'blob'}),
    ('invalid bytes field', {'type': 'data', 'blobId': 'blob', 'bytes': []}),
    ('invalid base64', {'type': 'data', 'blobId': 'blob', 'bytes': '!'}),
  ]) {
    test('$description throws FormatException', () {
      expect(
        () => BlobReplicationMessage.fromJson(json),
        throwsFormatException,
      );
    });
  }
}
