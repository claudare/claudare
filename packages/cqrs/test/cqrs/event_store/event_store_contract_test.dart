import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_result.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_dependency.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:test/test.dart';

final _startedAt = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);
final _completedAt = DateTime.fromMillisecondsSinceEpoch(200, isUtc: true);
final _occuredAt = DateTime.fromMillisecondsSinceEpoch(300, isUtc: true);

void main() {
  for (final backend in eventStoreTestBackends) {
    group('EventStore contract - ${backend.name}', () {
      late EventStoreTestSession session;
      late EventStore store;

      setUp(() async {
        session = await backend.open();
        store = session.store;
      });

      tearDown(() => session.close());

      test('empty reads and stream information', () async {
        final streamEvents = await store.getStreamEvents('missing', 10, 0);

        expect(streamEvents.originatingStreamVersion, 0);
        expect(streamEvents.events, isEmpty);

        final streamInfo = await store.getStreamInfo('missing');

        expect(streamInfo, isNull);

        final localEvents = await store.getLocalEvents(
          const PatternFilter.any(),
          0,
          10,
        );

        expect(localEvents.events, isEmpty);
        expect(localEvents.sequenceNumberCursor, isNull);

        final lastEvent = await store.getLocalLastEvent(
          const PatternFilter.any(),
        );

        expect(lastEvent.localSequence, 0);

        final statistics = await store.getStatistics();

        expect(statistics.eventCount, 0);
        expect(statistics.storageSize, 0);

        final commandRecords = await session.readCommandRecords();

        expect(commandRecords, isEmpty);
      });

      group('persistence', () {
        test('successful', () async {
          final dependencies = EventDependency({
            DeviceId(7): 3,
            DeviceId(8): 5,
          });

          await store.saveChanges(
            _command(deviceId: 9, kind: 'with-event'),
            StreamAppends(
              dependencies: dependencies,
              localLocks: const [
                StreamLocalLock(
                  streamId: 'test/1',
                  originatingStreamVersion: 0,
                ),
              ],
              events: [_event('test/1', 'created', detailLength: 2)],
            ),
          );

          final records = await session.readCommandRecords();

          expect(records, hasLength(1));

          final record = records.single;

          expect(record.localSequence, 1);
          expect(record.deviceId, DeviceId(9));
          expect(record.deviceSequence, 1);
          expect(record.kind, 'with-event');
          expect(record.detail, Uint8List.fromList([9, 1]));
          expect(record.startedAt, _startedAt);
          expect(record.completedAt, _completedAt);
          expect(record.dependencies.vector, {DeviceId(7): 3, DeviceId(8): 5});
          expect(record.nackReason, isNull);
          expect(record.exception, isNull);
        });

        test('empty', () async {
          await store.saveChanges(
            _command(deviceId: 9, kind: 'empty'),
            StreamAppends.empty(),
          );

          final records = await session.readCommandRecords();

          expect(records, hasLength(1));

          final record = records.single;

          expect(record.kind, 'empty');
          expect(record.dependencies.vector, isEmpty);
          expect(record.nackReason, isNull);
          expect(record.exception, isNull);
        });

        test('nacked', () async {
          await store.saveChanges(
            _command(
              deviceId: 9,
              kind: 'nacked',
              result: const CommandResult.nack(reason: 'invalid input'),
            ),
            StreamAppends.empty(),
          );

          final records = await session.readCommandRecords();

          expect(records, hasLength(1));

          final record = records.single;

          expect(record.kind, 'nacked');
          expect(record.nackReason, 'invalid input');
          expect(record.exception, isNull);
        });

        test('with exception', () async {
          await store.saveChanges(
            _command(
              deviceId: 9,
              kind: 'exception',
              result: CommandResult.exception(exception: Exception('failed')),
            ),
            StreamAppends.empty(),
          );

          final records = await session.readCommandRecords();

          expect(records, hasLength(1));

          final record = records.single;

          expect(record.kind, 'exception');
          expect(record.nackReason, isNull);
          expect(record.exception, 'Exception: failed');
        });
      });

      test('allocates command sequences independently per device', () async {
        await store.saveChanges(
          _command(deviceId: 1, kind: 'one'),
          StreamAppends.empty(),
        );
        await store.saveChanges(
          _command(deviceId: 2, kind: 'two'),
          StreamAppends.empty(),
        );
        await store.saveChanges(
          _command(deviceId: 1, kind: 'three'),
          StreamAppends.empty(),
        );

        final records = await session.readCommandRecords();
        expect(records.map((record) => record.localSequence), [1, 2, 3]);
        expect(records.map((record) => record.deviceSequence), [1, 1, 2]);
      });

      test('pages stream events', () async {
        await store.saveChanges(
          _command(),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: const [
              StreamLocalLock(streamId: 'test/1', originatingStreamVersion: 0),
            ],
            events: [for (var i = 0; i < 5; i++) _event('test/1', 'event-$i')],
          ),
        );

        final first = await store.getStreamEvents('test/1', 2, 0);

        expect(first.originatingStreamVersion, 5);
        expect(first.events.map((event) => event.encodedEvent.kind), [
          'event-0',
          'event-1',
        ]);
        expect(first.events.map((event) => event.streamVersion), [1, 2]);

        final second = await store.getStreamEvents('test/1', 2, 2);

        expect(second.events.map((event) => event.encodedEvent.kind), [
          'event-2',
          'event-3',
        ]);
        expect(second.events.map((event) => event.streamVersion), [3, 4]);

        final last = await store.getStreamEvents('test/1', 2, 4);

        expect(last.events.single.encodedEvent.kind, 'event-4');
        expect(last.events.single.streamVersion, 5);
      });

      group('projection events', () {
        test('all', () async {
          await store.saveChanges(
            _command(),
            StreamAppends(
              dependencies: EventDependency.empty(),
              localLocks: const [
                StreamLocalLock(
                  streamId: 'test/1',
                  originatingStreamVersion: 0,
                ),
                StreamLocalLock(
                  streamId: 'other/1',
                  originatingStreamVersion: 0,
                ),
              ],
              events: [_event('test/1', 'first'), _event('other/1', 'second')],
            ),
          );

          final first = await store.getLocalEvents(
            const PatternFilter.any(),
            0,
            1,
          );

          expect(first.events.single.encodedEvent.kind, 'first');
          expect(first.events.single.localSequence, 1);
          expect(first.sequenceNumberCursor, 1);

          final second = await store.getLocalEvents(
            const PatternFilter.any(),
            first.sequenceNumberCursor!,
            1,
          );

          expect(second.events.single.encodedEvent.kind, 'second');
          expect(second.events.single.streamId, 'other/1');
          expect(second.events.single.localSequence, 2);
          expect(second.sequenceNumberCursor, 2);
        });

        test('prefix', () async {
          await store.saveChanges(
            _command(),
            StreamAppends(
              dependencies: EventDependency.empty(),
              localLocks: const [
                StreamLocalLock(
                  streamId: 'test/1',
                  originatingStreamVersion: 0,
                ),
                StreamLocalLock(
                  streamId: 'other/1',
                  originatingStreamVersion: 0,
                ),
              ],
              events: [
                _event('test/1', 'matching'),
                _event('other/1', 'not-matching'),
              ],
            ),
          );

          final events = await store.getLocalEvents(
            const PatternFilter.startsWith('test/'),
            0,
            2,
          );

          expect(events.events, hasLength(1));
          expect(events.events.single.streamId, 'test/1');
          expect(events.events.single.encodedEvent.kind, 'matching');
          expect(events.events.single.localSequence, 1);
          expect(events.sequenceNumberCursor, 1);

          final lastEvent = await store.getLocalLastEvent(
            const PatternFilter.startsWith('test/'),
          );

          expect(lastEvent.localSequence, 1);
        });
      });

      test(
        'preserves multi-stream order and allocates event sequences',
        () async {
          final result = await store.saveChanges(
            _command(deviceId: 4),
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
                _event('account/a', 'a-1'),
                _event('account/b', 'b-1'),
                _event('account/a', 'a-2'),
              ],
            ),
          );

          expect(result.orders.map((order) => order.localSequence), [1, 2, 3]);

          final a = await store.getStreamEvents('account/a', 10, 0);

          expect(a.events.map((event) => event.streamVersion), [1, 2]);
          expect(a.events.map((event) => event.causalPair.sequence), [1, 3]);
          expect(
            a.events.every((event) => event.causalPair.deviceId == DeviceId(4)),
            isTrue,
          );

          final b = await store.getStreamEvents('account/b', 10, 0);

          expect(b.events.single.streamVersion, 1);
          expect(b.events.single.causalPair.sequence, 2);

          final all = await store.getLocalEvents(
            const PatternFilter.any(),
            0,
            10,
          );

          expect(all.events.map((event) => event.encodedEvent.kind), [
            'a-1',
            'b-1',
            'a-2',
          ]);

          final aInfo = await store.getStreamInfo('account/a');

          expect(aInfo!.originatingStreamVersion, 2);

          final bInfo = await store.getStreamInfo('account/b');

          expect(bInfo!.originatingStreamVersion, 1);
        },
      );

      test('stale locks roll back events and their command record', () async {
        await store.saveChanges(
          _command(kind: 'initial'),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: const [
              StreamLocalLock(
                streamId: 'account/a',
                originatingStreamVersion: 0,
              ),
            ],
            events: [_event('account/a', 'a-1')],
          ),
        );

        await expectLater(
          store.saveChanges(
            _command(kind: 'stale'),
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
              events: [_event('account/a', 'a-2'), _event('account/b', 'b-1')],
            ),
          ),
          throwsA(isA<ConcurrencyProblem>()),
        );

        final a = await store.getStreamEvents('account/a', 10, 0);

        expect(a.events, hasLength(1));

        final b = await store.getStreamEvents('account/b', 10, 0);

        expect(b.events, isEmpty);

        final commandRecords = await session.readCommandRecords();

        expect(commandRecords, hasLength(1));
      });

      test('reports statistics and resets all state and sequences', () async {
        await store.saveChanges(
          _command(deviceId: 6),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: const [
              StreamLocalLock(streamId: 'test/1', originatingStreamVersion: 0),
            ],
            events: [
              _event('test/1', 'first', detailLength: 3),
              _event('test/1', 'second', detailLength: 7),
            ],
          ),
        );

        final before = await store.getStatistics();
        expect(before.eventCount, 2);
        expect(before.storageSize, 10);

        await store.reset();

        final after = await store.getStatistics();

        expect(after.eventCount, 0);
        expect(after.storageSize, 0);

        final streamInfo = await store.getStreamInfo('test/1');

        expect(streamInfo, isNull);

        final commandRecords = await session.readCommandRecords();

        expect(commandRecords, isEmpty);

        final result = await store.saveChanges(
          _command(deviceId: 6),
          StreamAppends(
            dependencies: EventDependency.empty(),
            localLocks: const [
              StreamLocalLock(streamId: 'test/1', originatingStreamVersion: 0),
            ],
            events: [_event('test/1', 'after-reset')],
          ),
        );

        expect(result.orders.single.localSequence, 1);

        final streamEvents = await store.getStreamEvents('test/1', 1, 0);

        final event = streamEvents.events.single;
        expect(event.streamVersion, 1);
        expect(event.causalPair.sequence, 1);

        final records = await session.readCommandRecords();

        final command = records.single;
        expect(command.localSequence, 1);
        expect(command.deviceSequence, 1);
      });
    });
  }
}

StoredCommandWrite _command({
  int deviceId = 1,
  String kind = 'test',
  CommandResult result = const CommandResult.success(),
}) {
  return StoredCommandWrite(
    deviceId: DeviceId(deviceId),
    encoded: EncodedCommand(
      kind: kind,
      bytes: Uint8List.fromList([deviceId, 1]),
    ),
    startedAt: _startedAt,
    completedAt: _completedAt,
    result: result,
  );
}

StoredEventCommandWrite _event(
  String streamId,
  String kind, {
  int detailLength = 1,
}) {
  return StoredEventCommandWrite(
    streamId: streamId,
    encodedEvent: EncodedEvent(kind: kind, bytes: Uint8List(detailLength)),
    occuredAt: _occuredAt,
  );
}
