import 'dart:convert';

import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  for (final (type, wireType) in [
    (ProxyMessageType.direct, 'direct'),
    (ProxyMessageType.broadcast, 'broadcast'),
  ]) {
    test('$wireType preserves its payload through a JSON round trip', () {
      final original = ProxyMessage(
        type: type,
        actor: 'sender',
        data: '{"text":"hello\\nworld","count":2}',
      );

      final decoded = ProxyMessage.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.type, original.type);
      expect(decoded.actor, original.actor);
      expect(decoded.data, original.data);
    });
  }

  test('missing message type throws FormatException', () {
    expect(
      () => ProxyMessage.fromJson({'actor': 'sender', 'data': 'payload'}),
      throwsFormatException,
    );
  });

  for (final type in [null, 'unknown', 1]) {
    test('unsupported message type $type throws FormatException', () {
      expect(
        () => ProxyMessage.fromJson({
          'type': type,
          'actor': 'sender',
          'data': 'payload',
        }),
        throwsFormatException,
      );
    });
  }
}
