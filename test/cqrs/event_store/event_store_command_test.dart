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
        final res = await store.getStreamEvents("non-existing", 10, 0);

        expect(res.originatingVersion, 0);
        expect(res.versionCursor, isNull);
        expect(res.events.length, 0);
      });

      test("get empty stream info first", () async {
        final res = await store.getStreamInfoFirst("non-existing");

        expect(res, isNull);
      });

      test("get empty stream info last", () async {
        final res = await store.getStreamInfoLast("non-existing");

        expect(res, isNull);
      });

      test("single insertion and retrieval", () async {
        final streamId = "test";
        final deviceId = DeviceId(1);
        final t0 = DateTime.fromMillisecondsSinceEpoch(0);
        final t1 = DateTime.fromMillisecondsSinceEpoch(1000);
        final t2 = DateTime.fromMillisecondsSinceEpoch(2000);

        final insertRes = await store.multiAppendEvents(
          deviceId,
          _fakeCommand(startedAt: t0, completedAt: t1),
          StreamAppends(
            dependencies: EventDependency({}),
            locks: [StreamLock(streamId: streamId, originatingVersion: 0)],
            events: [_fakeEvent(streamId: streamId, occuredAt: t2)],
          ),
        );

        expect(insertRes.orders, hasLength(1));
        expect(insertRes.orders.first.localSequence, 1);
        expect(insertRes.orders.first.localVersion, 1);

        final retrieveRes = await store.getStreamEvents(streamId, 10, 0);
        final events = retrieveRes.events.toList();

        expect(events, hasLength(1));
        final e = events.first;
        expect(e.deviceId, deviceId);
        expect(e.causalSequence, 1);
        expect(e.kind, 'test');
        expect(e.detail, '{}');
        expect(e.occuredAt, t2);
      });
    });
  });
}

StoredCommandWrite _fakeCommand({
  required DateTime startedAt,
  required DateTime completedAt,
}) {
  return StoredCommandWrite(
    kind: 'test',
    detail: '{}',
    startedAt: startedAt,
    completedAt: completedAt,
  );
}

StoredEventCommandWrite _fakeEvent({
  required String streamId,
  required DateTime occuredAt,
}) {
  return StoredEventCommandWrite(
    streamId: streamId,
    kind: 'test',
    detail: '{}',
    occuredAt: occuredAt,
  );
}
