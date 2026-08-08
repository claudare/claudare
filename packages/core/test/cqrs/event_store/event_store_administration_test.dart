import 'dart:typed_data' show Uint8List;

import 'package:core/cqrs.dart';
import 'package:core/cqrs_test_utils.dart';
import 'package:core/device_id.dart';
import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event_command_write.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:test/test.dart';

void main() {
  for (var factory in getEventStoreFactories()) {
    group('EventStoreAdministration - ${factory.name}', () {
      late EventStore store;

      setUp(() async {
        store = await factory.create();
      });

      tearDown(() async {
        await factory.cleanup();
      });

      test('statistics', () async {
        final saveResult = await store.saveChanges(
          StoredCommandWrite(
            deviceId: DeviceId(9),
            encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
            startedAt: DateTime.now(),
            completedAt: DateTime.now(),
            result: CommandResult.success(),
          ),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: [
              StreamLocalLock(streamId: 'test', originatingStreamVersion: 0),
            ],
            events: [
              StoredEventCommandWrite(
                streamId: 'test',
                encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(3)),
                occuredAt: DateTime.now(),
              ),
              StoredEventCommandWrite(
                streamId: 'test',
                encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(7)),
                occuredAt: DateTime.now(),
              ),
            ],
          ),
        );

        expect(saveResult.orders.length, equals(2));

        final statistics = await store.getStatistics();

        expect(statistics.eventCount, equals(2));
        expect(statistics.storageSize, equals(10));
      });

      test('reset', () async {
        final saveResult = await store.saveChanges(
          StoredCommandWrite(
            deviceId: DeviceId(9),
            encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
            startedAt: DateTime.now(),
            completedAt: DateTime.now(),
            result: CommandResult.success(),
          ),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: [
              StreamLocalLock(streamId: 'test', originatingStreamVersion: 0),
            ],
            events: [
              StoredEventCommandWrite(
                streamId: 'test',
                encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(3)),
                occuredAt: DateTime.now(),
              ),
              StoredEventCommandWrite(
                streamId: 'test',
                encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(7)),
                occuredAt: DateTime.now(),
              ),
            ],
          ),
        );

        expect(saveResult.orders.length, equals(2));

        await store.reset();

        final statistics = await store.getStatistics();

        expect(statistics.eventCount, equals(0));
        expect(statistics.storageSize, equals(0));
      });
    });
  }
}
