import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_result.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/event_dependency.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:common/common.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite db;
  late SqliteEventStore store;

  setUp(() async {
    db = IsolateSqlite();
    await db.openInMemory();
    store = SqliteEventStore(db);
    await store.migrate();
  });

  tearDown(() => db.close());

  test(
    'persists empty command attempts with dependency and result details',
    () async {
      final dependency = EventDependency({DeviceId(2): 4, DeviceId(1): 3});
      final startedAt = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);
      final completedAt = DateTime.fromMillisecondsSinceEpoch(200, isUtc: true);

      await store.saveChanges(
        StoredCommandWrite(
          deviceId: DeviceId(9),
          encoded: EncodedCommand(
            kind: 'rename',
            bytes: Uint8List.fromList([1]),
          ),
          startedAt: startedAt,
          completedAt: completedAt,
          result: CommandResult.nack(reason: 'name already exists'),
        ),
        StreamAppends(
          dependencies: dependency,
          localLocks: const [],
          events: const [],
        ),
      );

      final row = await db.queryRow(
        '''SELECT device_id, device_sequence, kind, detail, started_at,
          completed_at, dependencies, nack_reason, exception
        FROM command_record''',
      );

      expect(row, isNotNull);
      expect(row![0], 9);
      expect(row[1], 1);
      expect(row[2], 'rename');
      expect(row[3], Uint8List.fromList([1]));
      expect(row[4], startedAt.millisecondsSinceEpoch);
      expect(row[5], completedAt.millisecondsSinceEpoch);
      expect(JsonConverter.decode<List<dynamic>>(row[6] as Uint8List), [
        [2, 4],
        [1, 3],
      ]);
      expect(row[7], 'name already exists');
      expect(row[8], isNull);
    },
  );

  test('forward migration preserves existing v1 event data', () async {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await store.saveChanges(
      _command(timestamp),
      StreamAppends(
        dependencies: EventDependency.empty(),
        localLocks: const [
          StreamLocalLock(streamId: 'note/1', originatingStreamVersion: 0),
        ],
        events: [_event('note/1', timestamp)],
      ),
    );

    await db.execute('DROP TABLE command_record');
    await db.execute('DELETE FROM migrations_event_store WHERE version = 2');

    await store.migrate();

    final events = await store.getStreamEvents('note/1', 10, 0);
    expect(events.events, hasLength(1));
    expect(events.events.single.encodedEvent.kind, 'created');
    expect(await db.queryValue<int>('SELECT COUNT(*) FROM command_record'), 0);
  });

  test('stale writes roll back their command record and events', () async {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await store.saveChanges(
      _command(timestamp),
      StreamAppends(
        dependencies: EventDependency.empty(),
        localLocks: const [
          StreamLocalLock(streamId: 'note/1', originatingStreamVersion: 0),
        ],
        events: [_event('note/1', timestamp)],
      ),
    );

    await expectLater(
      store.saveChanges(
        _command(timestamp),
        StreamAppends(
          dependencies: EventDependency.empty(),
          localLocks: const [
            StreamLocalLock(streamId: 'note/1', originatingStreamVersion: 0),
            StreamLocalLock(streamId: 'note/2', originatingStreamVersion: 0),
          ],
          events: [_event('note/1', timestamp), _event('note/2', timestamp)],
        ),
      ),
      throwsA(isA<ConcurrencyProblem>()),
    );

    expect(await db.queryValue<int>('SELECT COUNT(*) FROM command_record'), 1);
    expect(await db.queryValue<int>('SELECT COUNT(*) FROM event'), 1);
    expect(await db.queryValue<int>('SELECT COUNT(*) FROM stream'), 1);
  });

  test('reset clears persisted command records', () async {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await store.saveChanges(_command(timestamp), StreamAppends.empty());

    await store.reset();

    expect(await db.queryValue<int>('SELECT COUNT(*) FROM command_record'), 0);
  });
}

StoredCommandWrite _command(DateTime timestamp) {
  return StoredCommandWrite(
    deviceId: DeviceId(1),
    encoded: EncodedCommand(kind: 'create', bytes: Uint8List.fromList([1])),
    startedAt: timestamp,
    completedAt: timestamp,
    result: CommandResult.success(),
  );
}

StoredEventCommandWrite _event(String streamId, DateTime timestamp) {
  return StoredEventCommandWrite(
    streamId: streamId,
    encodedEvent: EncodedEvent(kind: 'created', bytes: Uint8List.fromList([2])),
    occuredAt: timestamp,
  );
}
