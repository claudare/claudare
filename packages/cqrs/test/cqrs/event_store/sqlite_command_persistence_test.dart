import 'dart:io';
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

  test('stores canonical string-key dependency bytes', () async {
    expect(
      await store.addStoredCommand(
        _bundle(
          CommandId('actor-3', 1),
          dependency: CommandDependency({'actor-2': 4, 'actor-1': 3}),
        ),
      ),
      isFalse,
    );
    expect(
      await store.addStoredCommand(_bundle(CommandId('actor-1', 1))),
      isTrue,
    );
    for (var i = 2; i <= 3; i++) {
      expect(
        await store.addStoredCommand(_bundle(CommandId('actor-1', i))),
        isTrue,
      );
    }
    for (var i = 1; i <= 4; i++) {
      expect(
        await store.addStoredCommand(_bundle(CommandId('actor-2', i))),
        isTrue,
      );
    }
    expect(
      await store.addStoredCommand(
        _bundle(
          CommandId('actor-3', 1),
          dependency: CommandDependency({'actor-2': 4, 'actor-1': 3}),
        ),
      ),
      isTrue,
    );
    final bytes = await sqlite.queryValue<Uint8List>(
      "SELECT dependency FROM command WHERE id_actor = 'actor-3'",
    );
    expect(JsonConverter.decode<Map<String, dynamic>>(bytes), {
      'actor-1': 3,
      'actor-2': 4,
    });
  });

  test('rolls back a failed bundle without id_sequence holes', () async {
    await sqlite.execute('''CREATE TRIGGER fail_event BEFORE INSERT ON event
      WHEN NEW.kind = 'fail'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');
    await expectLater(
      store.addStoredCommand(
        _bundle(CommandId('actor-3', 1), kind: 'fail', count: 2),
      ),
      throwsA(isA<EventStoreException>()),
    );
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM command'), 0);
    expect(await sqlite.queryValue<int>('SELECT COUNT(*) FROM event'), 0);
    expect(await store.getStreamVersion('one'), isNull);
    await sqlite.execute('DROP TRIGGER fail_event');
    expect(
      await store.addStoredCommand(_bundle(CommandId('actor-3', 1))),
      isTrue,
    );
    expect(
      (await store.getStoredCommand(CommandId('actor-3', 1)))!.toJson(),
      _bundle(CommandId('actor-3', 1)).toJson(),
    );
    expect((await database.getLogEvents(0)).data.single.position, 0);
  });

  test(
    'rolls back all local events and command allocation on failure',
    () async {
      await sqlite.execute('''CREATE TRIGGER fail_event BEFORE INSERT ON event
      WHEN NEW.id_index = 1
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');
      await expectLater(
        store.saveChanges(_changes('one', count: 2)),
        throwsA(isA<EventStoreException>()),
      );
      final failedState = await store.getState();
      expect(failedState.lastCommandLogPosition, isNull);
      expect(failedState.lastEventLogPosition, isNull);
      expect(failedState.logVersion, CommandDependency());
      expect(await store.getStreamVersion('one'), isNull);
      await sqlite.execute('DROP TRIGGER fail_event');
      await store.saveChanges(_changes('one', count: 2));
      final events = (await store.getLogEvents(0)).data;
      expect(events.map((event) => event.position), [0, 1]);
      expect(events.map((event) => event.version), [0, 1]);
      expect(
        await store.getStoredCommand(CommandId('test-actor', 1)),
        isNotNull,
      );
    },
  );

  test('separate stores sharing SQLite serialize stream lock checks', () async {
    final otherStore = SqliteEventStore(sqlite);
    await otherStore.migrate();
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
    expect(
      (await otherStore.getState()).logVersion,
      CommandDependency({'test-actor': 1}),
    );
  });

  test('separate stores share commands for the same actor', () async {
    final otherStore = SqliteEventStore(sqlite);
    await otherStore.migrate();
    final first = _bundle(CommandId('actor-160', 1));
    final second = _bundle(CommandId('actor-160', 2));
    expect(await store.addStoredCommand(first), isTrue);
    expect(
      (await otherStore.getStoredCommand(first.commandId))!.toJson(),
      first.toJson(),
    );
    expect(await otherStore.addStoredCommand(second), isTrue);
    expect(
      (await store.getStoredCommand(second.commandId))!.toJson(),
      second.toJson(),
    );
  });

  test('separate stores append a concurrent command only once', () async {
    final otherStore = SqliteEventStore(sqlite);
    await otherStore.migrate();
    final bundle = _bundle(CommandId('actor-160', 1));
    final results = await Future.wait([
      store.addStoredCommand(bundle),
      otherStore.addStoredCommand(bundle),
    ]);
    expect(results.where((accepted) => accepted), hasLength(1));
    expect(
      (await otherStore.getStoredCommand(bundle.commandId))!.toJson(),
      bundle.toJson(),
    );
  });

  test('reopening preserves actors and their next sequences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'event-store-keys-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final filepath = '${directory.path}/events.sqlite';
    final firstDatabase = IsolateSqlite();
    await firstDatabase.open(filepath);
    addTearDown(firstDatabase.close);
    final first = SqliteEventStore(firstDatabase);
    await first.migrate();
    await first.saveChanges(_changes('local'));
    final imported = _bundle(CommandId('actor-160', 1));
    expect(await first.addStoredCommand(imported), isTrue);
    await first.close();

    final secondDatabase = IsolateSqlite();
    await secondDatabase.open(filepath);
    addTearDown(secondDatabase.close);
    final second = SqliteEventStore(secondDatabase);
    await second.migrate();
    expect(
      (await second.getStoredCommand(imported.commandId))!.toJson(),
      imported.toJson(),
    );
    expect(
      (await second.getStoredCommand(
        CommandId('test-actor', 1),
      ))!.commandId.actor,
      'test-actor',
    );
    expect(
      await second.addStoredCommand(_bundle(CommandId('actor-160', 2))),
      isTrue,
    );
    expect(
      await second.addStoredCommand(_bundle(CommandId('actor-42', 1))),
      isTrue,
    );
    await second.saveChanges(_changes('local-next'));
    expect(
      (await second.getState()).logVersion,
      CommandDependency({'test-actor': 2, 'actor-160': 2, 'actor-42': 1}),
    );
    expect(
      (await second.getStoredCommand(
        CommandId('actor-160', 2),
      ))!.commandId.actor,
      imported.commandId.actor,
    );
    expect(
      (await second.getStoredCommand(
        CommandId('actor-42', 1),
      ))!.commandId.actor,
      'actor-42',
    );
  });

  test(
    'separate stores sharing SQLite allocate distinct command IDs',
    () async {
      final otherStore = SqliteEventStore(sqlite);
      await otherStore.migrate();
      await Future.wait([
        store.saveChanges(_changes('one')),
        otherStore.saveChanges(_changes('two')),
      ]);
      final state = await store.getState();
      expect(state.lastCommandLogPosition, 1);
      expect(state.lastEventLogPosition, 1);
      expect(state.logVersion, CommandDependency({'test-actor': 2}));
      expect(await store.getStreamVersion('one'), 0);
      expect(await otherStore.getStreamVersion('two'), 0);
    },
  );
}

CommandChanges _changes(String path, {int count = 1}) {
  final timestamp = DateTime.utc(2026);
  return CommandChanges(
    actor: 'test-actor',
    dependency: CommandDependency(),
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

StoredCommand _bundle(
  CommandId id, {
  CommandDependency? dependency,
  String kind = 'test',
  int count = 1,
}) {
  final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return StoredCommand(
    commandId: id,
    dependency: dependency ?? CommandDependency(),
    occuredAt: time,
    events: [
      for (var i = 0; i < count; i++)
        StoredCommandEvent(
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
