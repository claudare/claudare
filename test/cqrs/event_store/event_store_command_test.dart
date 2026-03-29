import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/memory/memory_event_store.dart';
import 'package:core/src/time_provider.dart';
import 'package:test/test.dart';

typedef EventStoreFactory = Future<EventStoreCommand> Function();

void main() {
  final implementations = <String, EventStoreFactory>{
    'InMemory': () async {
      final s = MemoryEventStore(timeProvider: FakeTimeProviderStatic.zero());
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
        final res = await store.getStreamEvents("test", "non-existing", 10, 0);

        expect(res.originatingVersion, 0);
        expect(res.events.length, 0);
      });

      test("get empty stream info", () async {
        final res = await store.getStreamInfo("test", "non-existing");

        expect(res, isNull);
      });

      test("single insertion and retrieval", () async {
        final streamId = "test";
        final deviceId = DeviceId(1);
        final t0 = DateTime.fromMillisecondsSinceEpoch(0);
        final t1 = DateTime.fromMillisecondsSinceEpoch(1000);
        final t2 = DateTime.fromMillisecondsSinceEpoch(2000);

        final insertRes = await store.multiAppendEvents(
          _fakeCommand(startedAt: t0, completedAt: t1),
          StreamAppends(
            dependencies: EventDependency({}),
            localLocks: [
              StreamLocalLock(streamId: streamId, originatingVersion: 0),
            ],
            events: [
              _fakeEvent(streamId: streamId, kind: "test", occuredAt: t2),
            ],
          ),
        );

        expect(insertRes.orders, hasLength(1));
        expect(insertRes.orders.first.localSequence, 1);
        expect(insertRes.orders.first.localVersion, 1);

        final retrieveRes = await store.getStreamEvents(
          "test",
          streamId,
          10,
          0,
        );
        final events = retrieveRes.events.toList();

        expect(events, hasLength(1));
        final e = events.first;
        expect(e.deviceId, deviceId);
        expect(e.causalSequence, 1);
        expect(e.encodedEvent.kind, 'test');
        expect(e.encodedEvent.detail, '{}');
        expect(e.occuredAt, t2);
      });

      test("get stream events", () async {
        final streamId = "test";
        final t0 = DateTime.fromMillisecondsSinceEpoch(0);
        final t1 = DateTime.fromMillisecondsSinceEpoch(1000);
        final t2 = DateTime.fromMillisecondsSinceEpoch(2000);

        await store.multiAppendEvents(
          _fakeCommand(startedAt: t0, completedAt: t1),
          StreamAppends(
            dependencies: EventDependency({}),
            localLocks: [
              StreamLocalLock(streamId: streamId, originatingVersion: 0),
            ],
            events: [
              _fakeEvent(streamId: streamId, kind: "test-1", occuredAt: t2),
              _fakeEvent(streamId: streamId, kind: "test-2", occuredAt: t2),
            ],
          ),
        );

        final res = await store.getStreamInfo("test", streamId);

        expect(res, isNotNull);
        expect(res!.originatingVersion, 2);

        // TODO: proper usage of sequences must be tested
        // Or maybe the sequencer is in the outside?
        expect(res.causalSequencePair.deviceId.value, 1);
        expect(res.causalSequencePair.sequence, 2);
      });

      // TODO: a group where all tests have x events inserted
      group("pagination", () {
        test("in the beginning", () async {
          final streamId = 'test';
          final t0 = DateTime.fromMillisecondsSinceEpoch(0);

          final insertRes = await store.multiAppendEvents(
            _fakeCommand(startedAt: t0, completedAt: t0),
            StreamAppends(
              dependencies: EventDependency({}),
              localLocks: [
                StreamLocalLock(streamId: streamId, originatingVersion: 0),
              ],
              events:
                  List.generate(
                    6,
                    (i) => _fakeEvent(
                      streamId: streamId,
                      kind: "event-$i",
                      occuredAt: t0,
                    ),
                  ).toList(),
            ),
          );

          expect(insertRes.orders.length, 6);

          final getRes = await store.getStreamEvents("test", streamId, 2, 0);
          final events = getRes.events.toList();
          expect(getRes.originatingVersion, 6);

          expect(getRes.events.length, 2);

          expect(events[0].encodedEvent.kind, "event-0");
          expect(events[1].encodedEvent.kind, "event-1");

          expect(events[0].localVersion, 1);
          expect(events[1].localVersion, 2);
        });

        test("in the middle", () async {
          final streamId = 'test';
          final t0 = DateTime.fromMillisecondsSinceEpoch(0);

          final insertRes = await store.multiAppendEvents(
            _fakeCommand(startedAt: t0, completedAt: t0),
            StreamAppends(
              dependencies: EventDependency({}),
              localLocks: [
                StreamLocalLock(streamId: streamId, originatingVersion: 0),
              ],
              events:
                  List.generate(
                    6,
                    (i) => _fakeEvent(
                      streamId: streamId,
                      kind: "event-$i",
                      occuredAt: t0,
                    ),
                  ).toList(),
            ),
          );

          expect(insertRes.orders.length, 6);

          final getRes = await store.getStreamEvents("test", streamId, 2, 2);
          final events = getRes.events.toList();
          expect(getRes.originatingVersion, 6);
          expect(getRes.events.length, 2);

          expect(events[0].encodedEvent.kind, 'event-2');
          expect(events[1].encodedEvent.kind, 'event-3');

          expect(events[0].localVersion, 3);
          expect(events[1].localVersion, 4);
        });
      });
    });
  });
}

StoredCommandWrite _fakeCommand({
  required DateTime startedAt,
  required DateTime completedAt,
}) {
  return StoredCommandWrite(
    applicationId: "test",
    deviceId: DeviceId(1),
    encoded: EncodedCommand(kind: 'test', detail: '{}'),
    startedAt: startedAt,
    completedAt: completedAt,
    result: CommandResult.success(),
  );
}

StoredEventCommandWrite _fakeEvent({
  required String streamId,
  required String kind,
  required DateTime occuredAt,
}) {
  return StoredEventCommandWrite(
    encodedEvent: EncodedEvent(kind: kind, detail: '{}'),
    streamId: streamId,

    occuredAt: occuredAt,
  );
}
