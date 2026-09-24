import 'dart:async';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event/stream_event.dart';
import 'package:test/test.dart';

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

void main() {
  test('memory backend is ready without initialization', () async {
    final session = await const MemoryEventDatabaseTestBackend().open();
    addTearDown(session.close);
    expect((await session.database.getState()).lastLocalEventSequence, 0);
    expect((await session.store.getStatistics()).eventCount, 0);
  });

  test('SQLite backend migrates and closes its database', () async {
    final session = await const SqliteEventDatabaseTestBackend().open();
    final database = session.database as SqliteEventDatabase;
    expect((await database.getState()).lastLocalEventSequence, 0);
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

      test('keeps staged records outside applied sequences', () async {
        for (final sequence in [1, 2]) {
          final command = _command(CommandId(1, sequence));
          final event = _event(command.commandId, 0, 'shared');
          await store.stageReplicatedCommand(command);
          await store.stageReplicatedEvents([event]);
          expect(
            await database.getPendingCommand(command.commandId),
            isNotNull,
          );
          expect(await database.getPendingEvent(event.eventId), event);
        }
        final state = await database.getState();
        expect(state.lastLocalCommandSequence, 0);
        expect(state.lastLocalEventSequence, 0);
        expect(state.appliedVersion, VersionVector());
      });

      test('reconstructs interleaved stream paths and versions', () async {
        for (final (sequence, paths) in [
          (1, ['one', 'two', 'one']),
          (2, ['two', 'one']),
        ]) {
          final commandId = CommandId(1, sequence);
          await database
              .appendApplied(_command(commandId, eventCount: paths.length), [
                for (var index = 0; index < paths.length; index++)
                  _event(commandId, index, paths[index]),
              ]);
        }
        expect(await database.getStreamVersion('one'), 3);
        expect(await database.getStreamVersion('two'), 2);
        final one = await database.getStreamEvents('one', 1, 10);
        expect(one.data.map((event) => event.streamVersion), [2, 3]);
        expect(one.data.map((event) => event.commandId), [
          CommandId(1, 1),
          CommandId(1, 2),
        ]);
        final local = await database.getLocalEvents(0, 10);
        expect(local.data.map((event) => event.streamPath), [
          'one',
          'two',
          'one',
          'two',
          'one',
        ]);
        expect(local.data.map((event) => event.localSequence), [1, 2, 3, 4, 5]);
        final applied = await database.getAppliedEvents(CommandId(1, 2));
        expect(
          applied.map((event) => (event.streamPath, event.streamVersion)),
          [('two', 2), ('one', 3)],
        );
        expect(
          (await database.getAppliedEvent(EventId(1, 1, 1)))?.streamPath,
          'two',
        );
      });

      test('rejects an invalid batch without applying records', () async {
        final commandId = CommandId(1, 1);
        await expectLater(
          database.appendApplied(_command(commandId, eventCount: 2), [
            _event(commandId, 0, 'shared'),
            _event(commandId, 2, 'shared'),
          ]),
          throwsA(anything),
        );
        expect(await database.getAppliedCommands(0, 1), isEmpty);
        expect((await database.getLocalEvents(0, 1)).data, isEmpty);
        expect(await database.getStreamVersion('shared'), 0);
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
        expect(state.lastLocalCommandSequence, 0);
        expect(state.lastLocalEventSequence, 0);
        await _append(failingStore);
        final command = (await database.getAppliedCommands(0, 1)).single;
        expect(command.localSequence, 1);
        expect(command.commandId.sequence, 1);
        expect(
          (await database.getAppliedEvents(
            command.commandId,
          )).single.streamVersion,
          1,
        );
      });

      test('does not signal a failed append', () async {
        final failingStore = EventStore(
          _FaultDatabase(database, failAppendOnce: true),
        );
        var appliedChanges = 0;
        final subscription = failingStore.appliedChanges.listen(
          (_) => appliedChanges++,
        );
        addTearDown(subscription.cancel);
        await expectLater(
          _append(failingStore),
          throwsA(isA<EventStoreException>()),
        );
        await _flushAsyncEvents();
        expect(appliedChanges, 0);
      });

      test('does not signal a failed promotion', () async {
        final failingStore = EventStore(
          _FaultDatabase(database, failPromotion: true),
        );
        final command = _command(CommandId(1, 1));
        await failingStore.stageReplicatedCommand(command);
        await failingStore.stageReplicatedEvents([
          _event(command.commandId, 0, 'test/1'),
        ]);
        var appliedChanges = 0;
        final subscription = failingStore.appliedChanges.listen(
          (_) => appliedChanges++,
        );
        addTearDown(subscription.cancel);
        await expectLater(
          failingStore.promotePendingCommand(command.commandId),
          throwsA(isA<EventStoreException>()),
        );
        await _flushAsyncEvents();
        expect(appliedChanges, 0);
      });

      test('listener failures do not alter a successful save', () async {
        final saveCompleted = Completer<void>();
        final listenerFailure = Completer<Object>();
        late StreamSubscription<void> subscription;
        runZonedGuarded<void>(() {
          subscription = store.appliedChanges.listen((_) {
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
        expect(
          (await database.getLocalEvents(0, 1)).data.single.localSequence,
          1,
        );
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

ReplicatedCommand _command(CommandId commandId, {int eventCount = 1}) =>
    ReplicatedCommand(
      commandId: commandId,
      dependency: VersionVector(),
      encoded: EncodedCommand(kind: 'remote', bytes: Uint8List(0)),
      startedAt: _timestamp,
      completedAt: _timestamp,
      eventCount: eventCount,
    );

ReplicatedEvent _event(CommandId commandId, int index, String streamPath) =>
    ReplicatedEvent(
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
    StreamLocalLock(streamPath: 'test/1', originatingStreamVersion: 0),
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
  Future<int> getStreamVersion(String streamPath) {
    if (_readFailure case final failure?) throw failure;
    return _database.getStreamVersion(streamPath);
  }

  @override
  Future<PaginatedResult<StreamEvent>> getStreamEvents(
    String path,
    int cursor,
    int count,
  ) => _database.getStreamEvents(path, cursor, count);
  @override
  Future<PaginatedResult<LocalEvent>> getLocalEvents(int cursor, int count) =>
      _database.getLocalEvents(cursor, count);
  @override
  Future<GetStatisticsResult> getStatistics() => _database.getStatistics();
  @override
  Future<ReplicatedCommand?> getAppliedCommand(CommandId id) =>
      _database.getAppliedCommand(id);
  @override
  Future<ReplicatedCommand?> getPendingCommand(CommandId id) =>
      _database.getPendingCommand(id);
  @override
  Future<ReplicatedEvent?> getAppliedEvent(EventId id) =>
      _database.getAppliedEvent(id);
  @override
  Future<ReplicatedEvent?> getPendingEvent(EventId id) =>
      _database.getPendingEvent(id);
  @override
  Future<List<AppliedCommand>> getAppliedCommands(int cursor, int count) =>
      _database.getAppliedCommands(cursor, count);
  @override
  Future<List<AppliedEvent>> getAppliedEvents(CommandId id) =>
      _database.getAppliedEvents(id);
  @override
  Future<void> appendApplied(
    ReplicatedCommand command,
    List<ReplicatedEvent> events,
  ) {
    if (_failAppendOnce) {
      _failAppendOnce = false;
      throw Exception('write failed');
    }
    return _database.appendApplied(command, events);
  }

  @override
  Future<void> stagePendingCommand(ReplicatedCommand command) =>
      _database.stagePendingCommand(command);
  @override
  Future<void> stagePendingEvents(List<ReplicatedEvent> events) =>
      _database.stagePendingEvents(events);
  @override
  Future<bool> promotePending(CommandId id) {
    if (_failPromotion) throw Exception('promotion failed');
    return _database.promotePending(id);
  }
}
