import 'dart:convert';

import 'package:test/test.dart';
import 'package:transport/transport.dart';

void main() {
  for (final name in ['', ' \t\n']) {
    test('constructors reject blank protocol ${jsonEncode(name)}', () {
      expect(
        () => MultiplexMessageData(protocol: name, generation: 0, data: ''),
        throwsArgumentError,
      );
      expect(
        () => MultiplexMessageReset(protocol: name, generation: 0),
        throwsArgumentError,
      );
    });
  }

  for (final protocol in ['commands', 'blobs', 'custom.protocol', ' spaced ']) {
    for (final message in <MultiplexMessage>[
      MultiplexMessageData(
        protocol: protocol,
        generation: 0,
        data: '{"text":"hello\\nworld","unicode":"café 🌍"}',
      ),
      MultiplexMessageReset(protocol: protocol, generation: 3),
    ]) {
      test('$protocol ${message.runtimeType} round trip', () {
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
    ('empty protocol', {'protocol': '', 'type': 'reset', 'generation': 0}),
    ('blank protocol', {'protocol': ' \t\n', 'type': 'reset', 'generation': 0}),
    ('non-string protocol', {'protocol': 42, 'type': 'reset', 'generation': 0}),
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
