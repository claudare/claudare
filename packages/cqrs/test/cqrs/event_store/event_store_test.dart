import 'dart:async';
import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/memory/memory_event_database.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:test/test.dart';

final _timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

void main() {
  test('reuses every generated sequence after a failed write', () async {
    final database = _FailOnceDatabase();
    final store = EventStore(database);

    await expectLater(_append(store), throwsA(isA<EventStoreException>()));
    expect((await database.getState()).lastLocalCommandSequence, 0);
    expect((await database.getState()).lastLocalEventSequence, 0);

    final result = await _append(store);
    expect(result.orders.single.localSequence, 1);
    final command = database.testAppliedCommands.single;
    expect(command.localSequence, 1);
    expect(command.commandId.sequence, 1);
    expect(database.testAppliedEvents.single.streamVersion, 1);
  });

  test('does not signal a failed append', () async {
    final store = EventStore(_FailOnceDatabase());
    var appliedChanges = 0;
    final subscription = store.appliedChanges.listen((_) => appliedChanges++);
    addTearDown(subscription.cancel);

    await expectLater(_append(store), throwsA(isA<EventStoreException>()));
    await _flushAsyncEvents();

    expect(appliedChanges, 0);
  });

  test('does not signal a failed promotion', () async {
    final store = EventStore(_PromotionFailingDatabase());
    final command = ReplicatedCommand(
      commandId: CommandId(1, 1),
      dependency: VersionVector(),
      encoded: EncodedCommand(kind: 'remote', bytes: Uint8List(0)),
      startedAt: _timestamp,
      completedAt: _timestamp,
      eventCount: 1,
    );
    final event = ReplicatedEvent(
      eventId: EventId(1, 1, 0),
      streamPath: 'test/1',
      encodedEvent: EncodedEvent(kind: 'created', bytes: Uint8List(0)),
      occuredAt: _timestamp,
    );
    await store.stageReplicatedCommand(command);
    await store.stageReplicatedEvents([event]);
    var appliedChanges = 0;
    final subscription = store.appliedChanges.listen((_) => appliedChanges++);
    addTearDown(subscription.cancel);

    await expectLater(
      store.promotePendingCommand(command.commandId),
      throwsA(isA<EventStoreException>()),
    );
    await _flushAsyncEvents();

    expect(appliedChanges, 0);
  });

  test('listener failures do not alter a successful save', () async {
    final database = MemoryEventDatabase();
    final store = EventStore(database);
    final saveCompleted = Completer<SaveChangesResult>();
    final listenerFailure = Completer<Object>();
    late StreamSubscription<void> subscription;

    runZonedGuarded<void>(() {
      subscription = store.appliedChanges.listen((_) {
        throw Exception('listener failed');
      });
      store
          .saveChanges(_changes())
          .then(saveCompleted.complete, onError: saveCompleted.completeError);
    }, (error, _) => listenerFailure.complete(error));
    addTearDown(subscription.cancel);

    final result = await saveCompleted.future;
    expect(result.orders.single.localSequence, 1);
    expect(database.testAppliedEvents.single.localSequence, 1);
    expect(await listenerFailure.future, isA<Exception>());
  });

  test('bubbles raw database Errors unchanged', () async {
    final failure = StateError('read failed');
    final store = EventStore(_ReadFailingDatabase(failure));

    await expectLater(store.getStreamInfo('test/1'), throwsA(same(failure)));
  });

  test('wraps raw database Exceptions', () async {
    final failure = Exception('read failed');
    final store = EventStore(_ReadFailingDatabase(failure));

    await expectLater(
      store.getStreamInfo('test/1'),
      throwsA(
        isA<EventStoreException>().having(
          (error) => error.cause,
          'cause',
          same(failure),
        ),
      ),
    );
  });
}

Future<SaveChangesResult> _append(EventStore store) =>
    store.saveChanges(_changes());

CommandChanges _changes() => CommandChanges(
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

class _FailOnceDatabase extends MemoryEventDatabase {
  bool _shouldFail = true;

  @override
  Future<void> appendApplied(
    AppliedCommand command,
    List<AppliedEvent> events,
  ) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw Exception('write failed');
    }
    await super.appendApplied(command, events);
  }
}

class _ReadFailingDatabase extends MemoryEventDatabase {
  final Object failure;

  _ReadFailingDatabase(this.failure);

  @override
  Future<int> getStreamVersion(String streamPath) async {
    throw failure;
  }
}

class _PromotionFailingDatabase extends MemoryEventDatabase {
  @override
  Future<void> promotePending(
    AppliedCommand command,
    List<AppliedEvent> events,
  ) async {
    throw Exception('promotion failed');
  }
}
