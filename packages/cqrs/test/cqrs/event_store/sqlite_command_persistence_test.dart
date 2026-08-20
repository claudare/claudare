import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite sqlite;
  late SqliteEventDatabase database;
  late EventStore store;

  setUp(() async {
    sqlite = IsolateSqlite();
    await sqlite.openInMemory();
    database = SqliteEventDatabase(sqlite);
    store = EventStore(database);
    await store.migrate();
  });

  tearDown(() => store.close());

  test('store closure closes the SQLite database', () async {
    await store.close();

    await expectLater(sqlite.queryValue<int>('SELECT 1'), throwsStateError);
  });

  test('stores canonical integer-key dependency bytes', () async {
    final command = _command(dependency: VersionVector({2: 4, -1: 3}));
    await store.stageReplicatedCommand(command);
    final bytes = await sqlite.queryValue<Uint8List>(
      'SELECT dependency FROM pending_command',
    );
    expect(JsonConverter.decode<List<dynamic>>(bytes), [
      [-1, 3],
      [2, 4],
    ]);
  });

  test('computes the applied frontier from commands', () async {
    final command = _command();
    await _stage(store, command, kind: 'ok');
    expect(await store.promotePendingCommand(command.commandId), isTrue);
    expect((await database.getState()).appliedVersion, VersionVector({3: 1}));
  });

  test('rolls back failed promotion without sequence holes', () async {
    final command = _command();
    await _stage(store, command, kind: 'fail');
    await sqlite.execute('''CREATE TRIGGER fail_event BEFORE INSERT ON event
      WHEN NEW.kind = 'fail'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');

    await expectLater(
      store.promotePendingCommand(command.commandId),
      throwsA(isA<EventStoreException>()),
    );
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM event'), 0);
    expect(
      await sqlite.queryValue<int>('SELECT COUNT(*) FROM applied_command'),
      0,
    );
    expect(
      await sqlite.queryValue<int>('SELECT COUNT(*) FROM pending_command'),
      1,
    );
    expect(
      await sqlite.queryValue<int>('SELECT COUNT(*) FROM pending_event'),
      1,
    );

    await sqlite.execute('DROP TRIGGER fail_event');
    expect(await store.promotePendingCommand(command.commandId), isTrue);
    final applied = (await database.getAppliedCommands(0, 10)).single;
    final event = (await database.getAppliedEvents(command.commandId)).single;
    expect(applied.localSequence, 1);
    expect(event.localSequence, 1);
    expect(event.streamVersion, 1);
  });
}

ReplicatedCommand _command({VersionVector? dependency}) => ReplicatedCommand(
  commandId: CommandId(3, 1),
  dependency: dependency ?? VersionVector(),
  encoded: EncodedCommand(kind: 'test', bytes: Uint8List.fromList([1])),
  startedAt: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
  completedAt: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
  eventCount: 1,
);

Future<void> _stage(
  EventStore store,
  ReplicatedCommand command, {
  required String kind,
}) async {
  await store.stageReplicatedCommand(command);
  await store.stageReplicatedEvents([
    ReplicatedEvent(
      eventId: EventId(
        command.commandId.deviceId,
        command.commandId.sequence,
        0,
      ),
      streamPath: 'test/1',
      encodedEvent: EncodedEvent(kind: kind, bytes: Uint8List(0)),
      occuredAt: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
    ),
  ]);
}
