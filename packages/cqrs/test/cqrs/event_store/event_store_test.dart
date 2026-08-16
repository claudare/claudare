import 'dart:typed_data';

import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
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

Future<SaveChangesResult> _append(EventStore store) => store.saveChanges(
  CommandChanges(
    encoded: EncodedCommand(kind: 'test', bytes: Uint8List(0)),
    startedAt: _timestamp,
    completedAt: _timestamp,
    locks: const [
      StreamLocalLock(streamId: 'test/1', originatingStreamVersion: 0),
    ],
    events: [
      EventAppend(
        streamId: 'test/1',
        encodedEvent: EncodedEvent(kind: 'created', bytes: Uint8List(0)),
        occuredAt: _timestamp,
      ),
    ],
  ),
);

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
  Future<int> getStreamVersion(String streamId) async {
    throw failure;
  }
}
