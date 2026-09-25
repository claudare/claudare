import 'dart:async';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/log_command.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/staged_command_conflict.dart';
import 'package:test/test.dart';

final _occuredAt = DateTime.fromMillisecondsSinceEpoch(300, isUtc: true);

void main() {
  group('staged IDs and flat conversions', () {
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
      final logCommand = LogCommand.fromStagedCommand(command, logPosition: 9);
      expect(
        stagedCommandsEqual(logCommand.toStagedCommand(), command),
        isTrue,
      );

      final event = _stagedEvent(command.commandId, 1, kind: 'second');
      final logEvent = LogEvent.fromStagedEvent(
        event,
        logPosition: 12,
        streamVersion: 4,
      );
      expect(logEvent.toStagedEvent(), event);
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

      test('log commands use device zero and contiguous sequences', () async {
        await store.saveChanges(
          _commandChanges(
            'create',
            logLocks: const [
              StreamLock(streamPath: 'test/1', originatingStreamVersion: null),
            ],
            events: [
              _eventAppend('test/1', 'created'),
              _eventAppend('test/1', 'renamed'),
            ],
          ),
        );
        await _appendOne(store, streamPath: 'test/2', kind: 'next');

        final commands = await session.readLogCommands();
        expect(commands.map((command) => command.commandId), [
          CommandId(0, 1),
          CommandId(0, 2),
        ]);
        expect(commands.map((command) => command.logPosition), [0, 1]);
        expect(commands.first.dependency, VersionVector());
        expect(commands.last.dependency, VersionVector());
        final events = await store.getLogEventsForCommand(
          commands.first.commandId,
        );
        expect(events.map((event) => event.eventId.index), [0, 1]);
        expect(events.map((event) => event.logPosition), [0, 1]);
        expect(events.map((event) => event.version), [0, 1]);
      });

      test('signals after a successful non-empty log append', () async {
        var signalCount = 0;
        final subscription = store.logChanges.listen((_) => signalCount++);
        addTearDown(subscription.cancel);

        await store.saveChanges(
          _commandChanges(
            'local',
            logLocks: const [
              StreamLock(streamPath: 'test/1', originatingStreamVersion: null),
            ],
            events: [
              _eventAppend('test/1', 'local-first'),
              _eventAppend('test/1', 'local-second'),
            ],
          ),
        );
        await _flushAsyncEvents();

        expect(signalCount, 1);
      });

      test('signals after a successful staged-command promotion', () async {
        final command = _commandRecord(device: 8, sequence: 1, eventCount: 2);
        await _stageComplete(store, command);
        var signalCount = 0;
        final subscription = store.logChanges.listen((_) => signalCount++);
        addTearDown(subscription.cancel);

        expect(await store.promoteStaged(command.commandId), isTrue);
        await _flushAsyncEvents();

        expect(signalCount, 1);
      });

      test('does not signal for an empty command', () async {
        var signalCount = 0;
        final subscription = store.logChanges.listen((_) => signalCount++);
        addTearDown(subscription.cancel);

        await store.saveChanges(
          _commandChanges('empty', logLocks: const [], events: const []),
        );
        await _flushAsyncEvents();

        expect(signalCount, 0);
      });

      test('does not signal for an unsuccessful promotion', () async {
        final command = _commandRecord(device: 8, sequence: 1, eventCount: 2);
        await store.stageCommand(command);
        await store.stageEvents([_stagedEvent(command.commandId, 0)]);
        var signalCount = 0;
        final subscription = store.logChanges.listen((_) => signalCount++);
        addTearDown(subscription.cancel);

        expect(await store.promoteStaged(command.commandId), isFalse);
        await _flushAsyncEvents();

        expect(signalCount, 0);
      });

      test('reads durable history from a log-change listener', () async {
        final read = Completer<List<LogEvent>>();
        final subscription = store.logChanges.listen((_) async {
          try {
            read.complete(await store.getLogEventReader(0).scan().toList());
          } on Exception catch (error, stackTrace) {
            read.completeError(error, stackTrace);
          }
        });
        addTearDown(subscription.cancel);

        await _appendOne(store, streamPath: 'test/1', kind: 'created');

        final events = await read.future;
        expect(events.map((event) => event.encodedEvent.kind), ['created']);
        expect(events.single.logPosition, 0);
      });

      test('rolls back stale locks without allocator holes', () async {
        await _appendOne(store, streamPath: 'test/1', kind: 'first');
        await expectLater(
          store.saveChanges(
            _commandChanges(
              'stale',
              logLocks: const [
                StreamLock(
                  streamPath: 'test/1',
                  originatingStreamVersion: null,
                ),
              ],
              events: [_eventAppend('test/1', 'stale')],
            ),
          ),
          throwsA(isA<ConcurrencyProblem>()),
        );
        await _appendOne(
          store,
          streamPath: 'test/1',
          kind: 'second',
          originatingVersion: 0,
        );
        final commands = await session.readLogCommands();
        expect(commands.map((command) => command.commandId.sequence), [1, 2]);
      });

      test('rejects a log command with an unavailable dependency', () async {
        await expectLater(
          store.saveChanges(
            _commandChanges(
              'invalid-dependency',
              dependency: VersionVector({7: 1}),
              logLocks: const [
                StreamLock(
                  streamPath: 'test/1',
                  originatingStreamVersion: null,
                ),
              ],
              events: [_eventAppend('test/1', 'created')],
            ),
          ),
          throwsStateError,
        );
        expect(await session.readLogCommands(), isEmpty);
      });

      test(
        'supports command-first, event-first, and partial staging',
        () async {
          final command = _commandRecord(device: 7, sequence: 1, eventCount: 2);
          final events = [
            _stagedEvent(command.commandId, 1, kind: 'second'),
            _stagedEvent(command.commandId, 0, kind: 'first'),
          ];

          await store.stageCommand(command);
          expect(await store.promoteStaged(command.commandId), isFalse);
          await store.stageEvents([events.first]);
          expect(await store.promoteStaged(command.commandId), isFalse);
          await store.stageEvents([events.last]);
          expect(await store.promoteStaged(command.commandId), isTrue);

          final orphan = _commandRecord(device: -9, sequence: 1);
          await store.stageEvents([_stagedEvent(orphan.commandId, 0)]);
          expect(await store.promoteStaged(orphan.commandId), isFalse);
          await store.stageCommand(orphan);
          expect(await store.promoteStaged(orphan.commandId), isTrue);
        },
      );

      test('accepts mixed command ids and arbitrary event order', () async {
        final a = _commandRecord(device: 1, sequence: 1, eventCount: 2);
        final b = _commandRecord(device: 2, sequence: 1);
        await store.stageEvents([
          _stagedEvent(a.commandId, 1, kind: 'a1'),
          _stagedEvent(b.commandId, 0, kind: 'b0'),
          _stagedEvent(a.commandId, 0, kind: 'a0'),
        ]);
        await store.stageCommand(a);
        await store.stageCommand(b);
        expect(await store.promoteStaged(b.commandId), isTrue);
        expect(await store.promoteStaged(a.commandId), isTrue);
        expect(
          (await store.getLogEventsForCommand(
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
        expect(await store.promoteStaged(a2.commandId), isFalse);
        expect(await store.promoteStaged(b1.commandId), isFalse);
        expect(await store.promoteStaged(a1.commandId), isTrue);
        expect(await store.promoteStaged(a2.commandId), isTrue);
        expect(await store.promoteStaged(b1.commandId), isTrue);
        expect((await session.database.getState()).logVersion.values, {
          1: 2,
          2: 1,
        });
      });

      test('keeps staged data invisible and promotes atomically', () async {
        final command = _commandRecord(device: 3, sequence: 1, eventCount: 2);
        await store.stageCommand(command);
        await store.stageEvents([_stagedEvent(command.commandId, 0)]);
        expect((await store.getStatistics()).eventCount, 0);
        expect(await session.readLogCommands(), isEmpty);
        expect(await store.promoteStaged(command.commandId), isFalse);
        expect((await store.getStatistics()).eventCount, 0);
        await store.stageEvents([_stagedEvent(command.commandId, 1)]);
        expect(await store.promoteStaged(command.commandId), isTrue);
        expect((await store.getStatistics()).eventCount, 2);
      });

      test('does not promote a staged batch with an event index gap', () async {
        final command = _commandRecord(device: 13, sequence: 1, eventCount: 2);
        await store.stageCommand(command);
        await store.stageEvents([
          _stagedEvent(command.commandId, 0),
          _stagedEvent(command.commandId, 2),
        ]);

        expect(await store.promoteStaged(command.commandId), isFalse);
        expect(await session.readLogCommands(), isEmpty);
        expect((await store.getStatistics()).eventCount, 0);
      });

      test('is idempotent and rejects conflicting event bytes', () async {
        final command = _commandRecord(device: 4, sequence: 1);
        final event = _stagedEvent(command.commandId, 0);
        expect(await store.stageCommand(command), StageCommandResult.staged);
        expect(
          await store.stageCommand(command),
          StageCommandResult.alreadyPresent,
        );
        await store.stageEvents([event]);
        expect(
          await store.stageEvents([event]),
          StageCommandResult.alreadyPresent,
        );
        await expectLater(
          store.stageEvents([
            _stagedEvent(command.commandId, 0, kind: 'changed'),
          ]),
          throwsA(isA<StagedCommandConflict>()),
        );
        expect(await store.promoteStaged(command.commandId), isTrue);
        expect(
          await store.stageCommand(command),
          StageCommandResult.alreadyPresent,
        );
        expect(
          await store.stageEvents([event]),
          StageCommandResult.alreadyPresent,
        );
      });

      test('reconstructs transport from separately queried log rows', () async {
        await store.saveChanges(
          _commandChanges(
            'command',
            logLocks: const [
              StreamLock(streamPath: 'one', originatingStreamVersion: null),
              StreamLock(streamPath: 'two', originatingStreamVersion: null),
            ],
            events: [
              _eventAppend('one', 'first'),
              _eventAppend('two', 'second'),
            ],
          ),
        );
        final log = (await store.getLogCommands(0)).single;
        final events = await store.getLogEventsForCommand(log.commandId);
        final command = log.toStagedCommand();
        expect(command.eventCount, 2);
        expect(events, hasLength(2));
        expect(events.map((event) => event.eventId.index), [0, 1]);
      });

      test('pages log commands by receiver-log sequence', () async {
        await _appendOne(store, streamPath: 'one', kind: 'one');
        await _appendOne(store, streamPath: 'two', kind: 'two');
        await _appendOne(store, streamPath: 'three', kind: 'three');
        expect(
          (await store.getLogCommands(0)).map((value) => value.logPosition),
          [0, 1],
        );
        expect(
          (await store.getLogCommands(2)).map((value) => value.logPosition),
          [2],
        );
      });

      test('scans events from one stream', () async {
        await _appendOne(store, streamPath: 'one', kind: 'one-a');
        await _appendOne(store, streamPath: 'two', kind: 'two');
        await _appendOne(
          store,
          streamPath: 'one',
          kind: 'one-b',
          originatingVersion: 0,
        );

        final streamEvents = await store.getStreamReader('one').scan().toList();
        expect(streamEvents.map((event) => event.encodedEvent.kind), [
          'one-a',
          'one-b',
        ]);
        expect(streamEvents.map((event) => event.eventId.commandId), [
          CommandId(0, 1),
          CommandId(0, 3),
        ]);
        expect(
          (await store.getStreamReader('one', fromVersion: 1).scan().toList())
              .map((event) => event.version),
          [1],
        );
      });

      test('appends only at the latest stream version', () async {
        for (var version = 0; version < 4; version++) {
          await _appendOne(
            store,
            streamPath: 'abc',
            kind: 'event-$version',
            originatingVersion: version == 0 ? null : version - 1,
          );
        }
        expect((await store.getStreamInfo('abc'))?.originatingStreamVersion, 3);
        for (final stale in [2, 4]) {
          await expectLater(
            _appendOne(
              store,
              streamPath: 'abc',
              kind: 'rejected',
              originatingVersion: stale,
            ),
            throwsA(isA<ConcurrencyProblem>()),
          );
        }
        await _appendOne(
          store,
          streamPath: 'abc',
          kind: 'accepted',
          originatingVersion: 3,
        );
        expect(
          (await store.getStreamReader('abc').scan().toList()).map(
            (event) => event.version,
          ),
          [0, 1, 2, 3, 4],
        );
      });

      test('pages all log events without filtering', () async {
        await _appendOne(store, streamPath: 'one', kind: 'one');
        await _appendOne(store, streamPath: 'two', kind: 'two');
        await _appendOne(store, streamPath: 'three', kind: 'three');

        final reader = store.getLogEventReader(0);
        expect(await reader.loadMore(), isTrue);
        expect(reader.currentPage.map((event) => event.logPosition), [0, 1]);
        expect(reader.currentPage.map((event) => event.streamPath), [
          'one',
          'two',
        ]);
        expect(await reader.loadMore(), isTrue);
        expect(reader.currentPage.map((event) => event.logPosition), [2]);
        expect(reader.currentPage.map((event) => event.streamPath), ['three']);
        expect(await reader.loadMore(), isFalse);
      });

      test('uses an inclusive log event cursor', () async {
        await _appendOne(store, streamPath: 'one', kind: 'one');
        await _appendOne(store, streamPath: 'two', kind: 'two');
        await _appendOne(store, streamPath: 'three', kind: 'three');

        final events = await store.getLogEventReader(2).scan().toList();

        expect(events.map((event) => event.encodedEvent.kind), ['three']);
        expect(events.single.logPosition, 2);
      });

      test('keeps log-event sequences contiguous across log append and '
          'promotion', () async {
        await _appendOne(store, streamPath: 'one', kind: 'one-a');
        final remote = _commandRecord(device: 6, sequence: 1, eventCount: 2);
        await _stageComplete(store, remote);
        expect(await store.promoteStaged(remote.commandId), isTrue);
        await _appendOne(
          store,
          streamPath: 'one',
          kind: 'one-b',
          originatingVersion: 0,
        );

        final events = await store.getLogEventReader(0).scan().toList();

        expect(events.map((event) => event.logPosition), [0, 1, 2, 3]);
        expect(events.map((event) => event.streamPath), [
          'one',
          'test/6',
          'test/6',
          'one',
        ]);
      });
    });
  }
}

Future<void> _flushAsyncEvents() => Future<void>.delayed(Duration.zero);

Future<void> _appendOne(
  EventStore store, {
  required String streamPath,
  required String kind,
  int? originatingVersion,
}) => store.saveChanges(
  _commandChanges(
    kind,
    logLocks: [
      StreamLock(
        streamPath: streamPath,
        originatingStreamVersion: originatingVersion,
      ),
    ],
    events: [_eventAppend(streamPath, kind)],
  ),
);

Future<void> _stageComplete(EventStore store, StagedCommand command) async {
  await store.stageCommand(command);
  await store.stageEvents([
    for (var i = command.eventCount - 1; i >= 0; i--)
      _stagedEvent(command.commandId, i),
  ]);
}

CommandChanges _commandChanges(
  String kind, {
  VersionVector? dependency,
  required List<StreamLock> logLocks,
  required List<EventAppend> events,
}) => CommandChanges(
  dependency: dependency ?? VersionVector(),
  occuredAt: _occuredAt,
  locks: logLocks,
  events: events,
);

EventAppend _eventAppend(String streamPath, String kind) => EventAppend(
  streamPath: streamPath,
  encodedEvent: EncodedEvent(
    kind: kind,
    bytes: Uint8List.fromList([kind.length]),
  ),
  occuredAt: _occuredAt,
);

StagedCommand _commandRecord({
  required int device,
  required int sequence,
  VersionVector? dependency,
  int eventCount = 1,
}) => StagedCommand(
  commandId: CommandId(device, sequence),
  dependency: dependency ?? VersionVector(),
  occuredAt: _occuredAt,
  eventCount: eventCount,
);

StagedEvent _stagedEvent(
  CommandId commandId,
  int index, {
  String kind = 'event',
}) => StagedEvent(
  eventId: EventId(commandId.deviceId, commandId.sequence, index),
  streamPath: 'test/${commandId.deviceId}',
  encodedEvent: EncodedEvent(
    kind: kind,
    bytes: Uint8List.fromList([kind.length, index]),
  ),
  occuredAt: _occuredAt,
);
