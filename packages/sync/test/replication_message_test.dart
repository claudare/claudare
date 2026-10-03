import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  for (final values in <Map<String, int>>[
    {},
    {'local': 2, 'remote': 5},
  ]) {
    test('dependency preserves history $values through JSON', () {
      final original = ReplicationMessageDependency(CommandDependency(values));

      expect(original.toJson(), {'type': 'dependency', 'dependencies': values});
      final decoded = _roundTrip(original) as ReplicationMessageDependency;

      expect(decoded.version, original.version);
    });
  }

  test('command preserves its events through JSON', () {
    final time = DateTime.utc(2026, 10, 3, 12, 30);
    final original = ReplicationMessageCommand(
      StoredCommand(
        commandId: const CommandId('local', 3),
        dependency: CommandDependency({'local': 2, 'remote': 5}),
        occuredAt: time,
        events: [
          StoredCommandEvent(
            streamPath: '/notes/first',
            encodedEvent: EncodedEvent(
              kind: 'created',
              bytes: Uint8List.fromList([0, 127, 128, 255]),
            ),
            occuredAt: time,
          ),
          StoredCommandEvent(
            streamPath: '/notes/second',
            encodedEvent: EncodedEvent(kind: 'updated', bytes: Uint8List(0)),
            occuredAt: time.add(const Duration(seconds: 1)),
          ),
        ],
      ),
    );

    expect(original.toJson(), {
      'type': 'command',
      'command': original.command.toJson(),
    });
    final decoded = _roundTrip(original) as ReplicationMessageCommand;

    expect(decoded.command.commandId, original.command.commandId);
    expect(decoded.command.dependency, original.command.dependency);
    expect(decoded.command.occuredAt, original.command.occuredAt);
    expect(decoded.command.events, hasLength(original.command.events.length));
    for (var index = 0; index < original.command.events.length; index++) {
      final expected = original.command.events[index];
      final actual = decoded.command.events[index];
      expect(actual.streamPath, expected.streamPath);
      expect(actual.encodedEvent.kind, expected.encodedEvent.kind);
      expect(actual.encodedEvent.bytes, expected.encodedEvent.bytes);
      expect(actual.occuredAt, expected.occuredAt);
    }
  });

  test('command ACK preserves its ID through JSON', () {
    const original = ReplicationMessageCommandAck(CommandId('local', 3));

    expect(original.toJson(), {
      'type': 'commandAck',
      'commandId': ['local', 3],
    });
    final decoded = _roundTrip(original) as ReplicationMessageCommandAck;

    expect(decoded.commandId, original.commandId);
  });

  test('missing message type throws FormatException', () {
    expect(() => ReplicationMessage.fromJson({}), throwsFormatException);
  });

  for (final type in [null, 'unknown', 1]) {
    test('unsupported message type $type throws FormatException', () {
      expect(
        () => ReplicationMessage.fromJson({'type': type}),
        throwsFormatException,
      );
    });
  }
}

ReplicationMessage _roundTrip(ReplicationMessage message) =>
    ReplicationMessage.fromJson(
      jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
    );
