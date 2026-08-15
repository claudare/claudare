import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_write.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/replicated_command_conflict.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:test/test.dart';

final _startedAt = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);
final _completedAt = DateTime.fromMillisecondsSinceEpoch(200, isUtc: true);
final _occuredAt = DateTime.fromMillisecondsSinceEpoch(300, isUtc: true);

void main() {
  group('replication IDs and flat conversions', () {
    test('keeps equality type-safe and includes event index', () {
      expect(Dot(-1, 2), isNot(CommandId(-1, 2)));
      expect(CommandId(-1, 2), isNot(Dot(-1, 2)));
      expect(EventId(-1, 2, 0), isNot(CommandId(-1, 2)));
      expect(EventId(-1, 2, 0), EventId(-1, 2, 0));
      expect(EventId(-1, 2, 0), isNot(EventId(-1, 2, 1)));
      expect(EventId(-1, 2, 3).commandId, CommandId(-1, 2));
      expect(() => EventId(1, 1, -1), throwsFormatException);
      expect(
        () => _commandRecord(device: 1, sequence: 1, eventCount: 0),
        throwsFormatException,
      );
    });

    test('converts commands and events in both directions', () {
      final command = _commandRecord(device: -5, sequence: 1, eventCount: 2);
      final appliedCommand = AppliedCommand.fromReplicatedCommand(
        command,
        localSequence: 9,
      );
      expect(
        replicatedCommandsEqual(appliedCommand.toReplicatedCommand(), command),
        isTrue,
      );

      final event = _replicatedEvent(command.commandId, 1, kind: 'second');
      final appliedEvent = AppliedEvent.fromReplicatedEvent(
        event,
        localSequence: 12,
        streamVersion: 4,
      );
      expect(
        replicatedEventsEqual(appliedEvent.toReplicatedEvent(), event),
        isTrue,
      );
    });

    test('exports applied events in transport order', () {
      final id = CommandId(3, 1);
      final events = [
        AppliedEvent.fromReplicatedEvent(
          _replicatedEvent(id, 1, kind: 'b'),
          localSequence: 2,
          streamVersion: 2,
        ),
        AppliedEvent.fromReplicatedEvent(
          _replicatedEvent(id, 0, kind: 'a'),
          localSequence: 1,
          streamVersion: 1,
        ),
      ];
      expect(
        ReplicatedEvent.fromAppliedEvents(
          events,
        ).map((event) => event.eventId.index),
        [0, 1],
      );
    });
  });

  for (final backend in eventStoreTestBackends) {
    group('EventStore contract - ${backend.name}', () {
      late EventStoreTestSession session;
      late EventStore store;

      setUp(() async {
        session = await backend.open();
        store = session.store;
      });

      tearDown(() => session.close());

      test('local commands use device zero and contiguous sequences', () async {
        final first = await store.saveChanges(
          _storedCommand('create'),
          StreamAppends(
            localLocks: const [
              StreamLocalLock(streamId: 'test/1', originatingStreamVersion: 0),
            ],
            events: [
              _storedEvent('test/1', 'created'),
              _storedEvent('test/1', 'renamed'),
            ],
          ),
        );
        await _appendOne(store, streamId: 'test/2', kind: 'next');

        expect(first.orders.map((order) => order.localSequence), [1, 2]);
        final commands = await session.readAppliedCommands();
        expect(commands.map((command) => command.commandId), [
          CommandId(0, 1),
          CommandId(0, 2),
        ]);
        expect(commands.map((command) => command.localSequence), [1, 2]);
        expect(commands.first.dependency, VersionVector());
        final events = await store.getAppliedEvents(commands.first.commandId);
        expect(events.map((event) => event.eventId.index), [0, 1]);
        expect(events.map((event) => event.localSequence), [1, 2]);
        expect(events.map((event) => event.streamVersion), [1, 2]);
      });

      test('rolls back stale locks without allocator holes', () async {
        await _appendOne(store, streamId: 'test/1', kind: 'first');
        await expectLater(
          store.saveChanges(
            _storedCommand('stale'),
            StreamAppends(
              localLocks: const [
                StreamLocalLock(
                  streamId: 'test/1',
                  originatingStreamVersion: 0,
                ),
              ],
              events: [_storedEvent('test/1', 'stale')],
            ),
          ),
          throwsA(isA<ConcurrencyProblem>()),
        );
        await _appendOne(
          store,
          streamId: 'test/1',
          kind: 'second',
          originatingVersion: 1,
        );
        final commands = await session.readAppliedCommands();
        expect(commands.map((command) => command.commandId.sequence), [1, 2]);
      });

      test(
        'supports command-first, event-first, and partial staging',
        () async {
          final command = _commandRecord(device: 7, sequence: 1, eventCount: 2);
          final events = [
            _replicatedEvent(command.commandId, 1, kind: 'second'),
            _replicatedEvent(command.commandId, 0, kind: 'first'),
          ];

          await store.stageReplicatedCommand(command);
          expect(await store.promotePendingCommand(command.commandId), isFalse);
          await store.stageReplicatedEvents([events.first]);
          expect(await store.promotePendingCommand(command.commandId), isFalse);
          await store.stageReplicatedEvents([events.last]);
          expect(await store.promotePendingCommand(command.commandId), isTrue);

          final orphan = _commandRecord(device: -9, sequence: 1);
          await store.stageReplicatedEvents([
            _replicatedEvent(orphan.commandId, 0),
          ]);
          expect(await store.promotePendingCommand(orphan.commandId), isFalse);
          await store.stageReplicatedCommand(orphan);
          expect(await store.promotePendingCommand(orphan.commandId), isTrue);
        },
      );

      test('accepts mixed command ids and arbitrary event order', () async {
        final a = _commandRecord(device: 1, sequence: 1, eventCount: 2);
        final b = _commandRecord(device: 2, sequence: 1);
        await store.stageReplicatedEvents([
          _replicatedEvent(a.commandId, 1, kind: 'a1'),
          _replicatedEvent(b.commandId, 0, kind: 'b0'),
          _replicatedEvent(a.commandId, 0, kind: 'a0'),
        ]);
        await store.stageReplicatedCommand(a);
        await store.stageReplicatedCommand(b);
        expect(await store.promotePendingCommand(b.commandId), isTrue);
        expect(await store.promotePendingCommand(a.commandId), isTrue);
        expect(
          (await store.getAppliedEvents(
            a.commandId,
          )).map((event) => event.eventId.index),
          [0, 1],
        );
      });

      test('waits for dependency and the next origin sequence', () async {
        final a1 = _commandRecord(device: 1, sequence: 1);
        final a2 = _commandRecord(
          device: 1,
          sequence: 2,
          dependency: VersionVector({1: 1}),
        );
        final b1 = _commandRecord(
          device: 2,
          sequence: 1,
          dependency: VersionVector({1: 2}),
        );
        for (final command in [a2, b1, a1]) {
          await _stageComplete(store, command);
        }
        expect(await store.promotePendingCommand(a2.commandId), isFalse);
        expect(await store.promotePendingCommand(b1.commandId), isFalse);
        expect(await store.promotePendingCommand(a1.commandId), isTrue);
        expect(await store.promotePendingCommand(a2.commandId), isTrue);
        expect(await store.promotePendingCommand(b1.commandId), isTrue);
        expect((await session.database.getState()).appliedVersion.values, {
          1: 2,
          2: 1,
        });
      });

      test('keeps pending data invisible and promotes atomically', () async {
        final command = _commandRecord(device: 3, sequence: 1, eventCount: 2);
        await store.stageReplicatedCommand(command);
        await store.stageReplicatedEvents([
          _replicatedEvent(command.commandId, 0),
        ]);
        expect((await store.getStatistics()).eventCount, 0);
        expect(await session.readAppliedCommands(), isEmpty);
        expect(await store.promotePendingCommand(command.commandId), isFalse);
        expect((await store.getStatistics()).eventCount, 0);
        await store.stageReplicatedEvents([
          _replicatedEvent(command.commandId, 1),
        ]);
        expect(await store.promotePendingCommand(command.commandId), isTrue);
        expect((await store.getStatistics()).eventCount, 2);
      });

      test(
        'is idempotent and rejects conflicting command or event bytes',
        () async {
          final command = _commandRecord(device: 4, sequence: 1);
          final event = _replicatedEvent(command.commandId, 0);
          expect(
            await store.stageReplicatedCommand(command),
            StageReplicatedCommandResult.staged,
          );
          expect(
            await store.stageReplicatedCommand(command),
            StageReplicatedCommandResult.alreadyPresent,
          );
          await store.stageReplicatedEvents([event]);
          expect(
            await store.stageReplicatedEvents([event]),
            StageReplicatedCommandResult.alreadyPresent,
          );
          await expectLater(
            store.stageReplicatedCommand(
              _commandRecord(device: 4, sequence: 1, kind: 'changed'),
            ),
            throwsA(isA<ReplicatedCommandConflict>()),
          );
          await expectLater(
            store.stageReplicatedEvents([
              _replicatedEvent(command.commandId, 0, kind: 'changed'),
            ]),
            throwsA(isA<ReplicatedCommandConflict>()),
          );
          expect(await store.promotePendingCommand(command.commandId), isTrue);
          expect(
            await store.stageReplicatedCommand(command),
            StageReplicatedCommandResult.alreadyPresent,
          );
          expect(
            await store.stageReplicatedEvents([event]),
            StageReplicatedCommandResult.alreadyPresent,
          );
        },
      );

      test(
        'reconstructs transport from separately queried applied rows',
        () async {
          await store.saveChanges(
            _storedCommand('command'),
            StreamAppends(
              localLocks: const [
                StreamLocalLock(streamId: 'one', originatingStreamVersion: 0),
                StreamLocalLock(streamId: 'two', originatingStreamVersion: 0),
              ],
              events: [
                _storedEvent('one', 'first'),
                _storedEvent('two', 'second'),
              ],
            ),
          );
          final applied = (await store.getAppliedCommands(0)).single;
          final events = await store.getAppliedEvents(applied.commandId);
          final command = applied.toReplicatedCommand();
          expect(command.eventCount, 2);
          expect(ReplicatedEvent.fromAppliedEvents(events), hasLength(2));
          expect(
            ReplicatedEvent.fromAppliedEvents(
              events,
            ).map((event) => event.eventId.index),
            [0, 1],
          );
        },
      );

      test('pages applied commands by receiver-local sequence', () async {
        await _appendOne(store, streamId: 'one', kind: 'one');
        await _appendOne(store, streamId: 'two', kind: 'two');
        await _appendOne(store, streamId: 'three', kind: 'three');
        expect(
          (await store.getAppliedCommands(
            0,
          )).map((value) => value.localSequence),
          [1, 2],
        );
        expect(
          (await store.getAppliedCommands(
            2,
          )).map((value) => value.localSequence),
          [3],
        );
      });

      test('scans stream and filtered global readers across pages', () async {
        await _appendOne(store, streamId: 'one', kind: 'one-a');
        await _appendOne(store, streamId: 'two', kind: 'two');
        await _appendOne(
          store,
          streamId: 'one',
          kind: 'one-b',
          originatingVersion: 1,
        );

        final streamEvents = await store.getStreamReader('one').scan().toList();
        expect(streamEvents.map((event) => event.encodedEvent.kind), [
          'one-a',
          'one-b',
        ]);

        final globalEvents =
            await store
                .getGlobalReader(PatternFilter.exact('one'), 1)
                .scan()
                .toList();
        expect(globalEvents.map((event) => event.encodedEvent.kind), ['one-b']);
        expect(globalEvents.single.localSequence, 3);
      });

      test('resets applied and orphan pending state', () async {
        await _appendOne(store, streamId: 'one', kind: 'one');
        final orphan = CommandId(10, 1);
        await store.stageReplicatedEvents([_replicatedEvent(orphan, 0)]);
        await store.reset();
        final state = await session.database.getState();
        expect(state.lastLocalCommandSequence, 0);
        expect(state.lastLocalEventSequence, 0);
        expect(state.appliedVersion, VersionVector());
      });
    });
  }
}

Future<void> _appendOne(
  EventStore store, {
  required String streamId,
  required String kind,
  int originatingVersion = 0,
}) => store.saveChanges(
  _storedCommand(kind),
  StreamAppends(
    localLocks: [
      StreamLocalLock(
        streamId: streamId,
        originatingStreamVersion: originatingVersion,
      ),
    ],
    events: [_storedEvent(streamId, kind)],
  ),
);

Future<void> _stageComplete(EventStore store, ReplicatedCommand command) async {
  await store.stageReplicatedCommand(command);
  await store.stageReplicatedEvents([
    for (var i = command.eventCount - 1; i >= 0; i--)
      _replicatedEvent(command.commandId, i),
  ]);
}

StoredCommandWrite _storedCommand(String kind) => StoredCommandWrite(
  encoded: _encodedCommand(kind),
  startedAt: _startedAt,
  completedAt: _completedAt,
);

EncodedCommand _encodedCommand(String kind) =>
    EncodedCommand(kind: kind, bytes: Uint8List.fromList([kind.length]));

StoredEventCommandWrite _storedEvent(String streamId, String kind) =>
    StoredEventCommandWrite(
      streamId: streamId,
      encodedEvent: EncodedEvent(
        kind: kind,
        bytes: Uint8List.fromList([kind.length]),
      ),
      occuredAt: _occuredAt,
    );

ReplicatedCommand _commandRecord({
  required int device,
  required int sequence,
  String kind = 'command',
  VersionVector? dependency,
  int eventCount = 1,
}) => ReplicatedCommand(
  commandId: CommandId(device, sequence),
  dependency: dependency ?? VersionVector(),
  encoded: _encodedCommand(kind),
  startedAt: _startedAt,
  completedAt: _completedAt,
  eventCount: eventCount,
);

ReplicatedEvent _replicatedEvent(
  CommandId commandId,
  int index, {
  String kind = 'event',
}) => ReplicatedEvent(
  eventId: EventId(commandId.deviceId, commandId.sequence, index),
  streamId: 'test/${commandId.deviceId}',
  encodedEvent: EncodedEvent(
    kind: kind,
    bytes: Uint8List.fromList([kind.length, index]),
  ),
  occuredAt: _occuredAt,
);
