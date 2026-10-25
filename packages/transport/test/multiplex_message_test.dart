import 'dart:convert';

import 'package:test/test.dart';
import 'package:transport/transport.dart';

void main() {
  for (final protocol in PeerProtocol.values) {
    for (final message in <MultiplexMessage>[
      MultiplexMessageData(
        protocol: protocol,
        generation: 0,
        data: '{"text":"hello\\nworld","unicode":"café 🌍"}',
      ),
      MultiplexMessageReset(protocol: protocol, generation: 3),
    ]) {
      test('${protocol.name} ${message.runtimeType} round trip', () {
        final decoded = MultiplexMessage.fromJson(
          jsonDecode(jsonEncode(message.toJson())),
        );
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded.toJson(), message.toJson());
      });
    }
  }

  for (final (description, json) in <(String, Object?)>[
    ('non-object', []),
    (
      'unknown protocol',
      {'protocol': 'unknown', 'type': 'reset', 'generation': 0},
    ),
    (
      'unknown type',
      {'protocol': 'commands', 'type': 'unknown', 'generation': 0},
    ),
    ('missing generation', {'protocol': 'commands', 'type': 'reset'}),
    (
      'negative generation',
      {'protocol': 'commands', 'type': 'reset', 'generation': -1},
    ),
    (
      'invalid data',
      {'protocol': 'blobs', 'type': 'data', 'generation': 0, 'data': 42},
    ),
  ]) {
    test('$description throws FormatException', () {
      expect(() => MultiplexMessage.fromJson(json), throwsFormatException);
    });
  }
}
