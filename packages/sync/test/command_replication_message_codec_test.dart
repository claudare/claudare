import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  const codec = CommandReplicationMessageCodec();

  for (final message in <CommandReplicationMessage>[
    CommandReplicationMessageDependency(CommandDependency({'local': 1})),
    CommandReplicationMessageCommand(
      StoredCommand(
        commandId: const CommandId('local', 2),
        dependency: CommandDependency({'local': 1}),
        occuredAt: DateTime.utc(2026, 10, 3),
        events: [
          StoredCommandEvent(
            streamPath: '/notes/first',
            encodedEvent: EncodedEvent(
              kind: 'created',
              bytes: Uint8List.fromList([0, 127, 128, 255]),
            ),
            occuredAt: DateTime.utc(2026, 10, 3),
          ),
        ],
      ),
    ),
    const CommandReplicationMessageCommandAck(CommandId('local', 2)),
  ]) {
    final type = message.toJson()['type'];

    test('$type preserves its fields through a codec round trip', () {
      final decoded = codec.decode(codec.encode(message));

      expect(decoded.runtimeType, message.runtimeType);
      expect(decoded.toJson(), message.toJson());
    });
  }

  test('bad message throws FormatException', () {
    expect(() => codec.decode('{}'), throwsFormatException);
  });

  test('non-object JSON throws FormatException', () {
    expect(() => codec.decode('[]'), throwsFormatException);
  });

  test('bad message type throws FormatException', () {
    expect(() => codec.decode('{"type":"bad"}'), throwsFormatException);
  });
}
