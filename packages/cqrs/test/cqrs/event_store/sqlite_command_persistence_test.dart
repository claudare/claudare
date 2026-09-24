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
    await database.migrate();
    store = EventStore(database);
  });

  tearDown(() => database.close());

  test('database closure closes the SQLite connection', () async {
    await database.close();

    await expectLater(sqlite.queryValue<int>('SELECT 1'), throwsStateError);
  });

  test('stores canonical integer-key dependency bytes', () async {
    final command = _command(dependency: VersionVector({2: 4, -1: 3}));
    await store.stageReplicatedCommand(command);
    final bytes = await sqlite.queryValue<Uint8List>(
      'SELECT dependency FROM command WHERE local_sequence < 0',
    );
    expect(JsonConverter.decode<List<dynamic>>(bytes), [
      [-1, 3],
      [2, 4],
    ]);
  });

  test('allocates decreasing staged sequences in unified tables', () async {
    await store.stageReplicatedCommand(_command());
    await store.stageReplicatedCommand(_command(sequence: 2));
    await store.stageReplicatedEvents([
      _event(EventId(3, 1, 0)),
      _event(EventId(3, 2, 0)),
    ]);

    final commands = await sqlite.query(
      'SELECT local_sequence FROM command ORDER BY sequence',
    );
    final events = await sqlite.query(
      'SELECT local_sequence, stream_version FROM event ORDER BY sequence',
    );
    expect(commands.map((row) => row[0]), [-1, -2]);
    expect(events.map((row) => row[0]), [-1, -2]);
    expect(events.map((row) => row[1]), [-1, -1]);
    expect((await database.getState()).appliedVersion, VersionVector());
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
    await sqlite.execute('''CREATE TRIGGER fail_event BEFORE UPDATE ON event
      WHEN NEW.kind = 'fail'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');

    await expectLater(
      store.promotePendingCommand(command.commandId),
      throwsA(isA<EventStoreException>()),
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM event WHERE local_sequence >= 0',
      ),
      0,
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM command WHERE local_sequence >= 0',
      ),
      0,
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM command WHERE local_sequence < 0',
      ),
      1,
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM event WHERE local_sequence < 0',
      ),
      1,
    );

    await sqlite.execute('DROP TRIGGER fail_event');
    expect(await store.promotePendingCommand(command.commandId), isTrue);
    final applied = (await database.getAppliedCommands(0, 10)).single;
    final event = (await database.getAppliedEvents(command.commandId)).single;
    expect(applied.localSequence, 0);
    expect(event.localSequence, 0);
    expect(event.version, 0);
  });
}

ReplicatedCommand _command({VersionVector? dependency, int sequence = 1}) =>
    ReplicatedCommand(
      commandId: CommandId(3, sequence),
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
    _event(
      EventId(command.commandId.deviceId, command.commandId.sequence, 0),
      kind: kind,
    ),
  ]);
}

ReplicatedEvent _event(EventId eventId, {String kind = 'test'}) =>
    ReplicatedEvent(
      eventId: eventId,
      streamPath: 'test/1',
      encodedEvent: EncodedEvent(kind: kind, bytes: Uint8List(0)),
      occuredAt: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
    );
