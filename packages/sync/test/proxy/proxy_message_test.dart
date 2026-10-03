import 'dart:convert';

import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  for (final (description, json) in <(String, Object?)>[
    ('non-object', []),
    ('missing actor', {'type': 'direct', 'data': 'payload'}),
    ('invalid payload', {'type': 'broadcast', 'actor': 'sender', 'data': 42}),
  ]) {
    test('$description throws FormatException', () {
      expect(() => ProxyMessage.fromJson(json), throwsFormatException);
    });
  }

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
