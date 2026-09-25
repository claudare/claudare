import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
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

  test('stores canonical integer-key dependency bytes', () async {
    expect(
      await store.saveBundle(
        _bundle(CommandId(3, 1), dependency: VersionVector({2: 4, -1: 3})),
      ),
      isFalse,
    );
    expect(await store.saveBundle(_bundle(CommandId(-1, 1))), isTrue);
    for (var i = 2; i <= 3; i++) {
      expect(await store.saveBundle(_bundle(CommandId(-1, i))), isTrue);
    }
    for (var i = 1; i <= 4; i++) {
      expect(await store.saveBundle(_bundle(CommandId(2, i))), isTrue);
    }
    expect(
      await store.saveBundle(
        _bundle(CommandId(3, 1), dependency: VersionVector({2: 4, -1: 3})),
      ),
      isTrue,
    );
    final bytes = await sqlite.queryValue<Uint8List>(
      'SELECT dependency FROM command WHERE device_id = 3',
    );
    expect(JsonConverter.decode<List<dynamic>>(bytes), [
      [-1, 3],
      [2, 4],
    ]);
  });

  test('schema rejects negative command and event log positions', () async {
    for (final statement in [
      '''INSERT INTO command(log_position, device_id, sequence,
        dependency, occured_at, event_count) VALUES (-1, 1, 1, X'5B5D', 0, 1)''',
      '''INSERT INTO event(log_position, device_id, sequence, event_index,
        stream_path, stream_version, kind, detail, occured_at)
        VALUES (-1, 1, 1, 0, 'one', 0, 'test', X'', 0)''',
    ]) {
      await expectLater(sqlite.execute(statement), throwsA(isA<Exception>()));
    }
  });

  test('rolls back a failed bundle without sequence holes', () async {
    await sqlite.execute('''CREATE TRIGGER fail_event BEFORE INSERT ON event
      WHEN NEW.kind = 'fail'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');
    await expectLater(
      store.saveBundle(_bundle(CommandId(3, 1), kind: 'fail')),
      throwsA(isA<EventStoreException>()),
    );
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM command'), 0);
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM event'), 0);
    await sqlite.execute('DROP TRIGGER fail_event');
    expect(await store.saveBundle(_bundle(CommandId(3, 1))), isTrue);
    expect((await database.getLogEvents(0, 10)).data.single.logPosition, 0);
  });
}

CommandBundle _bundle(
  CommandId id, {
  VersionVector? dependency,
  String kind = 'test',
}) {
  final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return CommandBundle(
    command: StagedCommand(
      commandId: id,
      dependency: dependency ?? VersionVector(),
      occuredAt: time,
      eventCount: 1,
    ),
    events: [
      StagedEvent(
        eventId: EventId(id.deviceId, id.sequence, 0),
        streamPath: 'one',
        encodedEvent: EncodedEvent(kind: kind, bytes: Uint8List(0)),
        occuredAt: time,
      ),
    ],
  );
}
