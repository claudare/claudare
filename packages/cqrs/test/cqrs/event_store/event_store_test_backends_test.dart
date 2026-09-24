import 'dart:async';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/log_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:test/test.dart';

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

void main() {
  test('memory backend is ready without initialization', () async {
    final session = await const MemoryEventDatabaseTestBackend().open();
    addTearDown(session.close);
    expect((await session.database.getState()).lastEventLogPosition, null);
    expect((await session.store.getStatistics()).eventCount, 0);
  });

  test('SQLite backend migrates and closes its database', () async {
    final session = await const SqliteEventDatabaseTestBackend().open();
    final database = session.database as SqliteEventDatabase;
    expect((await database.getState()).lastEventLogPosition, null);
    await session.close();
    await expectLater(database.getState(), throwsStateError);
  });

  for (final backend in eventStoreTestBackends) {
    group('${backend.name} test backend', () {
      late EventStoreTestSession session;
      late EventDatabase database;
      late EventStore store;

      setUp(() async {
        session = await backend.open();
        database = session.database;
        store = session.store;
      });
      tearDown(() => session.close());

      test('closes idempotently', () async {
        await session.close();
        await session.close();
      });

      test('keeps staged records outside log sequences', () async {
        for (final sequence in [1, 2]) {
          final command = _command(CommandId(1, sequence));
          final event = _event(command.commandId, 0, 'shared');
          await store.stageCommand(command);
          await store.stageEvents([event]);
          expect(await database.getStagedCommand(command.commandId), isNotNull);
          expect(await database.getStagedEvent(event.eventId), event);
        }
        final state = await database.getState();
        expect(state.lastCommandLogPosition, null);
        expect(state.lastEventLogPosition, null);
        expect(state.logVersion, VersionVector());
      });

      test('reconstructs interleaved stream paths and versions', () async {
        for (final (sequence, paths) in [
          (1, ['one', 'two', 'one']),
          (2, ['two', 'one']),
        ]) {
          final commandId = CommandId(1, sequence);
          await database
              .appendLog(_command(commandId, eventCount: paths.length), [
                for (var index = 0; index < paths.length; index++)
                  _event(commandId, index, paths[index]),
              ]);
        }
        expect(await database.getStreamVersion('one'), 2);
        expect(await database.getStreamVersion('two'), 1);
        final one = await database.getStreamEvents('one', 1, 10);
        expect(one.data.map((event) => event.version), [1, 2]);
        expect(one.data.map((event) => event.eventId.commandId), [
          CommandId(1, 1),
          CommandId(1, 2),
        ]);
        final log = await database.getLogEvents(0, 10);
        expect(log.data.map((event) => event.streamPath), [
          'one',
          'two',
          'one',
          'two',
          'one',
        ]);
        expect(log.data.map((event) => event.logPosition), [0, 1, 2, 3, 4]);
        expect(log.data.map((event) => event.version), [0, 0, 1, 1, 2]);
        expect(log.data.map((event) => event.eventId), [
          EventId(1, 1, 0),
          EventId(1, 1, 1),
          EventId(1, 1, 2),
          EventId(1, 2, 0),
          EventId(1, 2, 1),
        ]);
        expect(one.data.map((event) => event.logPosition), [2, 4]);
        expect(one.data.map((event) => event.streamPath), ['one', 'one']);
        expect(one.data.map((event) => event.eventId), [
          EventId(1, 1, 2),
          EventId(1, 2, 1),
        ]);
        final commandEvents = await database.getLogEventsForCommand(
          CommandId(1, 2),
        );
        expect(
          commandEvents.map((event) => (event.streamPath, event.version)),
          [('two', 1), ('one', 2)],
        );
        expect(
          (await database.getLogEvent(EventId(1, 1, 1)))?.streamPath,
          'two',
        );
      });

      test('pages an interleaved stream by version', () async {
        for (final (sequence, paths) in [
          (1, ['one', 'two', 'one']),
          (2, ['two', 'one']),
        ]) {
          final commandId = CommandId(1, sequence);
          await database
              .appendLog(_command(commandId, eventCount: paths.length), [
                for (var index = 0; index < paths.length; index++)
                  _event(commandId, index, paths[index]),
              ]);
        }

        var cursor = 0;
        final versions = <int>[];
        do {
          final page = await database.getStreamEvents('one', cursor, 1);
          if (page.data.isEmpty) break;
          versions.add(page.data.single.version);
          cursor = page.next!;
        } while (true);

        expect(versions, [0, 1, 2]);
      });

      test('rejects an invalid batch without applying records', () async {
        final commandId = CommandId(1, 1);
        await expectLater(
          database.appendLog(_command(commandId, eventCount: 2), [
            _event(commandId, 0, 'shared'),
            _event(commandId, 2, 'shared'),
          ]),
          throwsA(anything),
        );
        expect(await database.getLogCommands(0, 1), isEmpty);
        expect((await database.getLogEvents(0, 1)).data, isEmpty);
        expect(await database.getStreamVersion('shared'), null);
      });

      test('reuses generated sequences after a failed write', () async {
        final failingStore = EventStore(
          _FaultDatabase(database, failAppendOnce: true),
        );
        await expectLater(
          _append(failingStore),
          throwsA(isA<EventStoreException>()),
        );
        final state = await database.getState();
        expect(state.lastCommandLogPosition, null);
        expect(state.lastEventLogPosition, null);
        await _append(failingStore);
        final command = (await database.getLogCommands(0, 1)).single;
        expect(command.logPosition, 0);
        expect(command.commandId.sequence, 1);
        expect(
          (await database.getLogEventsForCommand(
            command.commandId,
          )).single.version,
          0,
        );
      });

      test('does not signal a failed append', () async {
        final failingStore = EventStore(
          _FaultDatabase(database, failAppendOnce: true),
        );
        var logChanges = 0;
        final subscription = failingStore.logChanges.listen(
          (_) => logChanges++,
        );
        addTearDown(subscription.cancel);
        await expectLater(
          _append(failingStore),
          throwsA(isA<EventStoreException>()),
        );
        await _flushAsyncEvents();
        expect(logChanges, 0);
      });

      test('does not signal a failed promotion', () async {
        final failingStore = EventStore(
          _FaultDatabase(database, failPromotion: true),
        );
        final command = _command(CommandId(1, 1));
        await failingStore.stageCommand(command);
        await failingStore.stageEvents([
          _event(command.commandId, 0, 'test/1'),
        ]);
        var logChanges = 0;
        final subscription = failingStore.logChanges.listen(
          (_) => logChanges++,
        );
        addTearDown(subscription.cancel);
        await expectLater(
          failingStore.promoteStaged(command.commandId),
          throwsA(isA<EventStoreException>()),
        );
        await _flushAsyncEvents();
        expect(logChanges, 0);
      });

      test('listener failures do not alter a successful save', () async {
        final saveCompleted = Completer<void>();
        final listenerFailure = Completer<Object>();
        late StreamSubscription<void> subscription;
        runZonedGuarded<void>(() {
          subscription = store.logChanges.listen((_) {
            throw Exception('listener failed');
          });
          store
              .saveChanges(_changes())
              .then(
                saveCompleted.complete,
                onError: saveCompleted.completeError,
              );
        }, (error, _) => listenerFailure.complete(error));
        addTearDown(subscription.cancel);
        await saveCompleted.future;
        expect((await database.getLogEvents(0, 1)).data.single.logPosition, 0);
        expect(await listenerFailure.future, isA<Exception>());
      });

      test('bubbles raw database Errors unchanged', () async {
        final failure = StateError('read failed');
        final failingStore = EventStore(
          _FaultDatabase(database, readFailure: failure),
        );
        await expectLater(
          failingStore.getStreamInfo('test/1'),
          throwsA(same(failure)),
        );
      });

      test('wraps raw database Exceptions', () async {
        final failure = Exception('read failed');
        final failingStore = EventStore(
          _FaultDatabase(database, readFailure: failure),
        );
        await expectLater(
          failingStore.getStreamInfo('test/1'),
          throwsA(
            isA<EventStoreException>().having(
              (error) => error.cause,
              'cause',
              same(failure),
            ),
          ),
        );
      });
    });
  }
}

StagedCommand _command(CommandId commandId, {int eventCount = 1}) =>
    StagedCommand(
      commandId: commandId,
      dependency: VersionVector(),
      encoded: EncodedCommand(kind: 'remote', bytes: Uint8List(0)),
      startedAt: _timestamp,
      completedAt: _timestamp,
      eventCount: eventCount,
    );

StagedEvent _event(CommandId commandId, int index, String streamPath) =>
    StagedEvent(
      eventId: EventId(commandId.deviceId, commandId.sequence, index),
      streamPath: streamPath,
      encodedEvent: EncodedEvent(kind: 'event', bytes: Uint8List(0)),
      occuredAt: _timestamp,
    );

Future<void> _append(EventStore store) => store.saveChanges(_changes());

CommandChanges _changes() => CommandChanges(
  dependency: VersionVector(),
  encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
  startedAt: _timestamp,
  completedAt: _timestamp,
  locks: const [
    StreamLock(streamPath: 'test/1', originatingStreamVersion: null),
  ],
  events: [
    EventAppend(
      streamPath: 'test/1',
      encodedEvent: EncodedEvent(kind: 'created', bytes: Uint8List(0)),
      occuredAt: _timestamp,
    ),
  ],
);

Future<void> _flushAsyncEvents() => Future<void>.delayed(Duration.zero);

class _FaultDatabase implements EventDatabase {
  final EventDatabase _database;
  bool _failAppendOnce;
  final bool _failPromotion;
  final Object? _readFailure;

  _FaultDatabase(
    this._database, {
    bool failAppendOnce = false,
    bool failPromotion = false,
    Object? readFailure,
  }) : _failAppendOnce = failAppendOnce,
       _failPromotion = failPromotion,
       _readFailure = readFailure;

  @override
  int get defaultEventFetchPageSize => _database.defaultEventFetchPageSize;
  @override
  Future<EventDatabaseState> getState() => _database.getState();
  @override
  Future<int?> getStreamVersion(String streamPath) {
    if (_readFailure case final failure?) throw failure;
    return _database.getStreamVersion(streamPath);
  }

  @override
  Future<PaginatedResult<LogEvent>> getStreamEvents(
    String path,
    int cursor,
    int count,
  ) => _database.getStreamEvents(path, cursor, count);
  @override
  Future<PaginatedResult<LogEvent>> getLogEvents(int cursor, int count) =>
      _database.getLogEvents(cursor, count);
  @override
  Future<GetStatisticsResult> getStatistics() => _database.getStatistics();
  @override
  Future<StagedCommand?> getLogCommand(CommandId id) =>
      _database.getLogCommand(id);
  @override
  Future<StagedCommand?> getStagedCommand(CommandId id) =>
      _database.getStagedCommand(id);
  @override
  Future<StagedEvent?> getLogEvent(EventId id) => _database.getLogEvent(id);
  @override
  Future<StagedEvent?> getStagedEvent(EventId id) =>
      _database.getStagedEvent(id);
  @override
  Future<List<LogCommand>> getLogCommands(int cursor, int count) =>
      _database.getLogCommands(cursor, count);
  @override
  Future<List<LogEvent>> getLogEventsForCommand(CommandId id) =>
      _database.getLogEventsForCommand(id);
  @override
  Future<void> appendLog(StagedCommand command, List<StagedEvent> events) {
    if (_failAppendOnce) {
      _failAppendOnce = false;
      throw Exception('write failed');
    }
    return _database.appendLog(command, events);
  }

  @override
  Future<void> stageCommand(StagedCommand command) =>
      _database.stageCommand(command);
  @override
  Future<void> stageEvents(List<StagedEvent> events) =>
      _database.stageEvents(events);
  @override
  Future<bool> promoteStaged(CommandId id) {
    if (_failPromotion) throw Exception('promotion failed');
    return _database.promoteStaged(id);
  }
}
