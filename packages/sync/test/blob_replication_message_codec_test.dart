import 'dart:typed_data';

import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  const codec = BlobReplicationMessageCodec();
  final messages = <BlobReplicationMessage>[
    const BlobReplicationMessageRequest(blobId: 'blob'),
    BlobReplicationMessageData(
      blobId: 'blob',
      bytes: Uint8List.fromList([0, 127, 128, 255]),
    ),
    const BlobReplicationMessageMissing(blobId: 'absent'),
  ];

  for (final message in messages) {
    final type = message.toJson()['type'];
    test('$type preserves its fields through a codec round trip', () {
      final decoded = codec.decode(codec.encode(message));
      expect(decoded.runtimeType, message.runtimeType);
      expect(decoded.toJson(), message.toJson());
    });
  }

  test('stream conversion preserves messages and order', () async {
    final decoded = await Stream.fromIterable(messages)
        .transform(codec.encoder)
        .transform(codec.decoder)
        .toList();
    expect(
      decoded.map((message) => message.toJson()),
      messages.map((message) => message.toJson()),
    );
  });

  test('malformed JSON throws FormatException', () {
    expect(() => codec.decode('{'), throwsFormatException);
  });
}
