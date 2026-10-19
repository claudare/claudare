import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  for (final (description, json) in <(String, Object?)>[
    ('non-object', []),
    ('missing command', {'type': 'command'}),
    (
      'invalid dependency sequence',
      {
        'type': 'dependency',
        'dependencies': {'a': 'one'},
      },
    ),
    (
      'invalid ACK fields',
      {
        'type': 'commandAck',
        'commandId': ['a', null],
      },
    ),
    (
      'invalid nested event',
      {
        'type': 'command',
        'command': {
          'commandId': ['a', 1],
          'dependency': <String, dynamic>{},
          'occuredAt': '2026-10-03T00:00:00Z',
          'events': [null],
        },
      },
    ),
  ]) {
    test('$description throws FormatException', () {
      expect(
        () => CommandReplicationMessage.fromJson(json),
        throwsFormatException,
      );
    });
  }

  for (final values in <Map<String, int>>[
    {},
    {'local': 2, 'remote': 5},
  ]) {
    test('dependency preserves history $values through JSON', () {
      final original = CommandReplicationMessageDependency(
        CommandDependency(values),
      );

      expect(original.toJson(), {'type': 'dependency', 'dependencies': values});
      final decoded =
          _roundTrip(original) as CommandReplicationMessageDependency;

      expect(decoded.version, original.version);
    });
  }

  test('command preserves its events through JSON', () {
    final time = DateTime.utc(2026, 10, 3, 12, 30);
    final original = CommandReplicationMessageCommand(
      StoredCommand(
        blobIds: const [],
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
    final decoded = _roundTrip(original) as CommandReplicationMessageCommand;

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
    const original = CommandReplicationMessageCommandAck(CommandId('local', 3));

    expect(original.toJson(), {
      'type': 'commandAck',
      'commandId': ['local', 3],
    });
    final decoded = _roundTrip(original) as CommandReplicationMessageCommandAck;

    expect(decoded.commandId, original.commandId);
  });

  test('missing message type throws FormatException', () {
    expect(() => CommandReplicationMessage.fromJson({}), throwsFormatException);
  });

  for (final type in [null, 'unknown', 1]) {
    test('unsupported message type $type throws FormatException', () {
      expect(
        () => CommandReplicationMessage.fromJson({'type': type}),
        throwsFormatException,
      );
    });
  }
}

CommandReplicationMessage _roundTrip(CommandReplicationMessage message) =>
    CommandReplicationMessage.fromJson(
      jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
    );
