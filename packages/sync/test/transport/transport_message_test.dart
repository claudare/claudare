import 'dart:convert';

import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  for (final message in const <TransportMessage>[
    TransportMessageDiscovery(),
    TransportMessageHandshake('session-1'),
    TransportMessageHandshakeAck('session-1'),
    TransportMessageData(
      sessionId: 'session-1',
      data: '{"text":"hello\\nworld","unicode":"café 🌍"}',
    ),
    TransportMessageKeepalive('session-1'),
    TransportMessageClose('session-1'),
  ]) {
    final type = message.toJson()['type'];

    test('$type preserves its fields through a JSON round trip', () {
      final decoded = TransportMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.runtimeType, message.runtimeType);
      expect(decoded.toJson(), message.toJson());
    });
  }

  test('bad message throws FormatException', () {
    expect(
      () => TransportMessage.fromJson({'bad': 'message'}),
      throwsFormatException,
    );
  });

  test('bad message type throws FormatException', () {
    expect(
      () => TransportMessage.fromJson({'type': 'bad'}),
      throwsFormatException,
    );
  });
}
