import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/command_result.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  test('persists empty command attempts', () async {
    final store = MemoryEventStore();
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    await store.saveChanges(
      StoredCommandWrite(
        deviceId: DeviceId(1),
        encoded: EncodedCommand(kind: 'create', bytes: Uint8List(0)),
        startedAt: timestamp,
        completedAt: timestamp,
        result: CommandResult.nack(reason: 'invalid input'),
      ),
      StreamAppends.empty(),
    );

    expect(store.testAllCommands, hasLength(1));
    expect(store.testAllCommands.single.nackReason, 'invalid input');
  });
}
