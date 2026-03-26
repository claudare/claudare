import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:test/test.dart';

typedef EventStoreFactory = Future<EventStoreCommand> Function();

void main() {
  final implementations = <String, EventStoreFactory>{
    'InMemory': () async {
      final s = MemoryEventStore(
        getTime: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      return s;
    },
    // 'SQL': () async {
    //   final s = await createSqlEventStore();
    //   return s;
    // },
  };

  implementations.forEach((name, factory) {
    group('EventStoreCommand - $name', () {
      late EventStoreCommand store;

      setUp(() async {
        store = await factory();
      });

      tearDown(() async {
        // TODOs
      });

      test("get empty stream events", () async {
        final res = await store.getStreamEventsCursor("non-existing", 10, null);

        expect(res.originatingVersion, equals(0));
        expect(res.versionCursor, equals(null));
        expect(res.events.length, equals(0));
      });

      test("get empty stream info", () async {
        final res = await store.getStreamInfo("non-existing");

        expect(res.totalEventCount, equals(0));
        expect(res.firstCausalSequencePair, equals(null));
        expect(res.lastCausalSequencePair, equals(null));
      });

      test("single insertion and retrieval", () async {
        final streamId = "test";

        final insertRes = await store.multiAppendEvents(
          DeviceId(1),
          StoredCommandWrite(
            kind: '',
            detail: '',
            startedAt: DateTime.fromMillisecondsSinceEpoch(0),
            completedAt: DateTime.fromMillisecondsSinceEpoch(1000),
            dependencies: EventDependency(),
          ),
          StreamAppends(
            locks: [StreamLock(streamIdStr: streamId, originatingVersion: 0)],
            events: [
              StoredEventCommandWrite(
                streamId: streamId,
                kind: 'test',
                detail: '{}',
                metadata: '{}',
                createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
              ),
            ],
          ),
        );

        expect(insertRes.orders.length, equals(1));
        expect(insertRes.orders.first.localSequence, equals(1));
        expect(insertRes.orders.first.version, equals(1));

        final retrieveRes = await store.getStreamEventsCursor(
          streamId,
          10,
          null,
        );

        expect(retrieveRes.events.length, equals(1));
        expect(retrieveRes.events.first.deviceId, equals(DeviceId(1)));
        expect(retrieveRes.events.first.causalSequence, equals(1));
        expect(retrieveRes.events.first.kind, equals('test'));
        expect(retrieveRes.events.first.detail, equals('{}'));
        expect(retrieveRes.events.first.metadata, equals('{}'));
        expect(
          retrieveRes.events.first.createdAt,
          equals(DateTime.fromMillisecondsSinceEpoch(2000)),
        );
      });
    });
  });
}
