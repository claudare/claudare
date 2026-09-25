import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite sqlite;
  late SqliteEventStore database;
  late EventStore store;

  setUp(() async {
    sqlite = IsolateSqlite();
    await sqlite.openInMemory();
    database = SqliteEventStore(sqlite);
    await database.migrate();
    store = database;
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
      store.saveBundle(_bundle(CommandId(3, 1), kind: 'fail', count: 2)),
      throwsA(isA<EventStoreException>()),
    );
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM command'), 0);
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM event'), 0);
    expect(await store.getStreamVersion('one'), isNull);
    await sqlite.execute('DROP TRIGGER fail_event');
    expect(await store.saveBundle(_bundle(CommandId(3, 1))), isTrue);
    expect((await database.getLogEvents(0)).data.single.position, 0);
  });

  test(
    'rolls back all local events and command allocation on failure',
    () async {
      await sqlite.execute('''CREATE TRIGGER fail_event BEFORE INSERT ON event
      WHEN NEW.event_index = 1
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');
      await expectLater(
        store.saveChanges(_changes('one', count: 2)),
        throwsA(isA<EventStoreException>()),
      );
      final failedState = await store.getState();
      expect(failedState.lastCommandLogPosition, isNull);
      expect(failedState.lastEventLogPosition, isNull);
      expect(failedState.logVersion, VersionVector());
      expect(await store.getStreamVersion('one'), isNull);
      await sqlite.execute('DROP TRIGGER fail_event');
      await store.saveChanges(_changes('one', count: 2));
      final events = (await store.getLogEvents(0)).data;
      expect(events.map((event) => event.position), [0, 1]);
      expect(events.map((event) => event.version), [0, 1]);
      expect(await store.getBundle(CommandId(0, 1)), isNotNull);
    },
  );

  test('separate stores sharing SQLite serialize stream lock checks', () async {
    final otherStore = SqliteEventStore(sqlite);
    Future<bool> save(EventStore target) async {
      try {
        await target.saveChanges(_changes('one'));
        return true;
      } on ConcurrencyProblem {
        return false;
      }
    }

    final results = await Future.wait([save(store), save(otherStore)]);
    expect(results.where((saved) => saved), hasLength(1));
    expect((await store.getStatistics()).eventCount, 1);
    expect((await otherStore.getState()).logVersion, VersionVector({0: 1}));
  });

  test(
    'separate stores sharing SQLite allocate distinct command IDs',
    () async {
      final otherStore = SqliteEventStore(sqlite);
      await Future.wait([
        store.saveChanges(_changes('one')),
        otherStore.saveChanges(_changes('two')),
      ]);
      final state = await store.getState();
      expect(state.lastCommandLogPosition, 1);
      expect(state.lastEventLogPosition, 1);
      expect(state.logVersion, VersionVector({0: 2}));
      expect(await store.getStreamVersion('one'), 0);
      expect(await otherStore.getStreamVersion('two'), 0);
    },
  );
}

CommandChanges _changes(String path, {int count = 1}) {
  final timestamp = DateTime.utc(2026);
  return CommandChanges(
    dependency: VersionVector(),
    occuredAt: timestamp,
    locks: [StreamLock(streamPath: path, originatingStreamVersion: null)],
    events: [
      for (var i = 0; i < count; i++)
        EventAppend(
          streamPath: path,
          encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
          occuredAt: timestamp,
        ),
    ],
  );
}

CommandBundle _bundle(
  CommandId id, {
  VersionVector? dependency,
  String kind = 'test',
  int count = 1,
}) {
  final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return CommandBundle(
    commandId: id,
    dependency: dependency ?? VersionVector(),
    occuredAt: time,
    events: [
      for (var i = 0; i < count; i++)
        BundledEvent(
          streamPath: 'one',
          encodedEvent: EncodedEvent(
            kind: i == count - 1 ? kind : 'test',
            bytes: Uint8List(0),
          ),
          occuredAt: time,
        ),
    ],
  );
}
