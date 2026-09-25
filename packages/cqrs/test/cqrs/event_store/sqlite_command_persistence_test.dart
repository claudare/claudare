import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
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
    await store.stageCommand(command);
    final bytes = await sqlite.queryValue<Uint8List>(
      'SELECT dependency FROM command WHERE log_position < 0',
    );
    expect(JsonConverter.decode<List<dynamic>>(bytes), [
      [-1, 3],
      [2, 4],
    ]);
  });

  test('allocates decreasing staged sequences in unified tables', () async {
    await store.stageCommand(_command());
    await store.stageCommand(_command(sequence: 2));
    await store.stageEvents([
      _event(EventId(3, 1, 0)),
      _event(EventId(3, 2, 0)),
    ]);

    final commands = await sqlite.query(
      'SELECT log_position FROM command ORDER BY sequence',
    );
    final events = await sqlite.query(
      'SELECT log_position, stream_version FROM event ORDER BY sequence',
    );
    expect(commands.map((row) => row[0]), [-1, -2]);
    expect(events.map((row) => row[0]), [-1, -2]);
    expect(events.map((row) => row[1]), [-1, -1]);
    expect((await database.getState()).logVersion, VersionVector());
  });

  test('computes the log frontier from commands', () async {
    final command = _command();
    await _stage(store, command, kind: 'ok');
    expect(await store.promoteStaged(command.commandId), isTrue);
    expect((await database.getState()).logVersion, VersionVector({3: 1}));
  });

  test('rolls back failed promotion without sequence holes', () async {
    final command = _command();
    await _stage(store, command, kind: 'fail');
    await sqlite.execute('''CREATE TRIGGER fail_event BEFORE UPDATE ON event
      WHEN NEW.kind = 'fail'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');

    await expectLater(
      store.promoteStaged(command.commandId),
      throwsA(isA<EventStoreException>()),
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM event WHERE log_position >= 0',
      ),
      0,
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM command WHERE log_position >= 0',
      ),
      0,
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM command WHERE log_position < 0',
      ),
      1,
    );
    expect(
      await sqlite.queryValue<int>(
        'SELECT COUNT(*) FROM event WHERE log_position < 0',
      ),
      1,
    );

    await sqlite.execute('DROP TRIGGER fail_event');
    expect(await store.promoteStaged(command.commandId), isTrue);
    final log = (await database.getLogCommands(0, 10)).single;
    final event =
        (await database.getLogEventsForCommand(command.commandId)).single;
    expect(log.logPosition, 0);
    expect(event.logPosition, 0);
    expect(event.version, 0);
  });
}

StagedCommand _command({VersionVector? dependency, int sequence = 1}) =>
    StagedCommand(
      commandId: CommandId(3, sequence),
      dependency: dependency ?? VersionVector(),
      startedAt: DateTime.fromMillisecondsSinceEpoch(100, isUtc: true),
      completedAt: DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
      eventCount: 1,
    );

Future<void> _stage(
  EventStore store,
  StagedCommand command, {
  required String kind,
}) async {
  await store.stageCommand(command);
  await store.stageEvents([
    _event(
      EventId(command.commandId.deviceId, command.commandId.sequence, 0),
      kind: kind,
    ),
  ]);
}

StagedEvent _event(EventId eventId, {String kind = 'test'}) => StagedEvent(
  eventId: eventId,
  streamPath: 'test/1',
  encodedEvent: EncodedEvent(kind: kind, bytes: Uint8List(0)),
  occuredAt: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
);
