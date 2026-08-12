import 'dart:typed_data' show Uint8List;

import 'package:core/cqrs_test_utils.dart';
import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/event/stored_event_command_write.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:common/common.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:test/test.dart';

void main() {
  for (var factory in getEventStoreFactories()) {
    group('EventStoreCommand - ${factory.name}', () {
      late EventStoreCommand store;

      setUp(() async {
        store = await factory.create();
      });

      tearDown(() async {
        await factory.cleanup();
      });

      test('get empty stream events', () async {
        final res = await store.getStreamEvents('non-existing', 10, 0);

        expect(res.originatingStreamVersion, 0);
        expect(res.events.length, 0);
      });

      test('get empty stream info', () async {
        final res = await store.getStreamInfo('non-existing');

        expect(res, isNull);
      });

      test('single insertion', () async {
        final streamId = 'test';
        final deviceId = DeviceId(1);
        final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final t1 = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
        final t2 = DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true);

        final insertRes = await store.saveChanges(
          _fakeCommand(startedAt: t0, completedAt: t1),
          StreamAppends(
            dependencies: EventDependency({}),
            localLocks: [
              StreamLocalLock(streamId: streamId, originatingStreamVersion: 0),
            ],
            events: [
              _fakeEvent(streamId: streamId, kind: 'test', occuredAt: t2),
            ],
          ),
        );

        expect(insertRes.orders, hasLength(1));
        expect(insertRes.orders.first.localSequence, 1);

        final retrieveRes = await store.getStreamEvents(streamId, 10, 0);
        final events = retrieveRes.events.toList();

        expect(events, hasLength(1));
        final e = events.first;
        expect(e.causalPair.deviceId, deviceId);
        expect(e.causalPair.sequence, 1);
        expect(e.encodedEvent.kind, 'test');
        expect(e.encodedEvent.bytes, Uint8List.fromList([1, 2, 3]));
        expect(e.occuredAt, t2);
      });

      test('get stream events', () async {
        final streamId = 'test';
        final t0 = DateTime.fromMillisecondsSinceEpoch(0);
        final t1 = DateTime.fromMillisecondsSinceEpoch(1000);
        final t2 = DateTime.fromMillisecondsSinceEpoch(2000);

        await store.saveChanges(
          _fakeCommand(startedAt: t0, completedAt: t1),
          StreamAppends(
            dependencies: EventDependency({}),
            localLocks: [
              StreamLocalLock(streamId: streamId, originatingStreamVersion: 0),
            ],
            events: [
              _fakeEvent(streamId: streamId, kind: 'test-1', occuredAt: t2),
              _fakeEvent(streamId: streamId, kind: 'test-2', occuredAt: t2),
            ],
          ),
        );

        final res = await store.getStreamInfo(streamId);

        expect(res, isNotNull);
        expect(res!.originatingStreamVersion, 2);

        expect(res.causalSequencePair.deviceId.value, 1);
        expect(res.causalSequencePair.sequence, 2);
      });

      group('pagination', () {
        late String streamId;
        late DateTime t0;

        setUp(() async {
          streamId = 'test';
          t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

          final insertRes = await store.saveChanges(
            _fakeCommand(startedAt: t0, completedAt: t0),
            StreamAppends(
              dependencies: EventDependency({}),
              localLocks: [
                StreamLocalLock(
                  streamId: streamId,
                  originatingStreamVersion: 0,
                ),
              ],
              events:
                  List.generate(
                    6,
                    (i) => _fakeEvent(
                      streamId: streamId,
                      kind: 'event-$i',
                      occuredAt: t0,
                    ),
                  ).toList(),
            ),
          );

          expect(insertRes.orders, hasLength(6));
        });

        test('in the beginning', () async {
          final getRes = await store.getStreamEvents(streamId, 2, 0);
          final events = getRes.events.toList();

          expect(getRes.originatingStreamVersion, 6);
          expect(getRes.events.length, 2);

          expect(events[0].encodedEvent.kind, 'event-0');
          expect(events[1].encodedEvent.kind, 'event-1');

          expect(events[0].streamVersion, 1);
          expect(events[1].streamVersion, 2);
        });

        test('in the middle', () async {
          final getRes = await store.getStreamEvents(streamId, 2, 2);
          final events = getRes.events.toList();

          expect(getRes.originatingStreamVersion, 6);
          expect(getRes.events.length, 2);

          expect(events[0].encodedEvent.kind, 'event-2');
          expect(events[1].encodedEvent.kind, 'event-3');

          expect(events[0].streamVersion, 3);
          expect(events[1].streamVersion, 4);
        });

        test('in the end', () async {
          final getRes = await store.getStreamEvents(streamId, 99, 4);
          final events = getRes.events.toList();

          expect(getRes.originatingStreamVersion, 6);
          expect(getRes.events.length, 2);

          expect(events[0].encodedEvent.kind, 'event-4');
          expect(events[1].encodedEvent.kind, 'event-5');

          expect(events[0].streamVersion, 5);
          expect(events[1].streamVersion, 6);
        });
      });

      test('concurrency check', () async {
        final streamId = 'test';
        final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

        final insertRes = await store.saveChanges(
          _fakeCommand(startedAt: t0, completedAt: t0),
          StreamAppends(
            dependencies: EventDependency({}),
            localLocks: [
              StreamLocalLock(streamId: streamId, originatingStreamVersion: 0),
            ],
            events: [
              _fakeEvent(streamId: streamId, kind: 'event-0', occuredAt: t0),
            ],
          ),
        );

        expect(insertRes.orders, hasLength(1));

        // emit the saveChanged with the same originating stream version
        await expectLater(
          store.saveChanges(
            _fakeCommand(startedAt: t0, completedAt: t0),
            StreamAppends(
              dependencies: EventDependency({}),
              localLocks: [
                StreamLocalLock(
                  streamId: streamId,
                  originatingStreamVersion: 0,
                ),
              ],
              events: [
                _fakeEvent(streamId: streamId, kind: 'event-1', occuredAt: t0),
              ],
            ),
          ),
          throwsA(isA<ConcurrencyProblem>()),
        );

        // ensure that events were not emitted
        final readRes = await store.getStreamEvents(streamId, 10, 0);

        expect(readRes.originatingStreamVersion, 1);
        expect(readRes.events, hasLength(1));
        expect(readRes.events.first.encodedEvent.kind, 'event-0');
      });

      test(
        'multi-stream insertion preserves event order and versions',
        () async {
          final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

          final result = await store.saveChanges(
            _fakeCommand(startedAt: t0, completedAt: t0),
            StreamAppends(
              dependencies: EventDependency.empty(),
              localLocks: const [
                StreamLocalLock(
                  streamId: 'account/a',
                  originatingStreamVersion: 0,
                ),
                StreamLocalLock(
                  streamId: 'account/b',
                  originatingStreamVersion: 0,
                ),
              ],
              events: [
                _fakeEvent(streamId: 'account/a', kind: 'a-1', occuredAt: t0),
                _fakeEvent(streamId: 'account/b', kind: 'b-1', occuredAt: t0),
                _fakeEvent(streamId: 'account/a', kind: 'a-2', occuredAt: t0),
              ],
            ),
          );

          expect(result.orders.map((order) => order.localSequence), [1, 2, 3]);
          expect(
            (await store.getStreamInfo('account/a'))!.originatingStreamVersion,
            2,
          );
          expect(
            (await store.getStreamInfo('account/b'))!.originatingStreamVersion,
            1,
          );
          expect(
            (await store.getStreamEvents(
              'account/a',
              10,
              0,
            )).events.map((event) => event.encodedEvent.kind),
            ['a-1', 'a-2'],
          );
        },
      );

      test('stale multi-stream locks roll back every event', () async {
        final t0 = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

        await store.saveChanges(
          _fakeCommand(startedAt: t0, completedAt: t0),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: const [
              StreamLocalLock(
                streamId: 'account/a',
                originatingStreamVersion: 0,
              ),
            ],
            events: [
              _fakeEvent(streamId: 'account/a', kind: 'a-1', occuredAt: t0),
            ],
          ),
        );

        await expectLater(
          store.saveChanges(
            _fakeCommand(startedAt: t0, completedAt: t0),
            StreamAppends(
              dependencies: EventDependency.empty(),
              localLocks: const [
                StreamLocalLock(
                  streamId: 'account/a',
                  originatingStreamVersion: 0,
                ),
                StreamLocalLock(
                  streamId: 'account/b',
                  originatingStreamVersion: 0,
                ),
              ],
              events: [
                _fakeEvent(streamId: 'account/a', kind: 'a-2', occuredAt: t0),
                _fakeEvent(streamId: 'account/b', kind: 'b-1', occuredAt: t0),
              ],
            ),
          ),
          throwsA(isA<ConcurrencyProblem>()),
        );

        expect(
          (await store.getStreamEvents('account/a', 10, 0)).events,
          hasLength(1),
        );
        expect(
          (await store.getStreamEvents('account/b', 10, 0)).events,
          isEmpty,
        );
      });
    });
  }
}

StoredCommandWrite _fakeCommand({
  required DateTime startedAt,
  required DateTime completedAt,
}) {
  return StoredCommandWrite(
    deviceId: DeviceId(1),
    encoded: EncodedCommand(kind: 'test', bytes: Uint8List.fromList([1, 2, 3])),
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
    encodedEvent: EncodedEvent(
      kind: kind,
      bytes: Uint8List.fromList([1, 2, 3]),
    ),
    streamId: streamId,

    occuredAt: occuredAt,
  );
}
