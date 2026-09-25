import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  test('memory backend returns a ready store', () async {
    final session = await const MemoryEventStoreTestBackend().open();
    addTearDown(session.close);
    expect((await session.store.getState()).lastEventLogPosition, null);
    expect((await session.store.getStatistics()).eventCount, 0);
  });

  test('SQLite backend closes its database', () async {
    final session = await const SqliteEventStoreTestBackend().open();
    final database = session.store as SqliteEventStore;
    await session.close();
    await expectLater(database.getState(), throwsStateError);
  });

  for (final backend in eventStoreTestBackends) {
    group('${backend.name} database', () {
      late EventStoreTestSession session;
      late EventStore database;

      setUp(() async {
        session = await backend.open();
        database = session.store;
      });
      tearDown(() => session.close());

      test('reconstructs interleaved stream paths', () async {
        expect(
          await database.addStoredCommand(
            _bundle(CommandId('actor-1', 1), ['one', 'two', 'one']),
          ),
          isTrue,
        );
        expect(
          await database.addStoredCommand(
            _bundle(CommandId('actor-1', 2), ['two', 'one']),
          ),
          isTrue,
        );

        expect(await database.getStreamVersion('one'), 2);
        expect(await database.getStreamVersion('two'), 1);
        final one = await database.getStreamEvents('one', 1);
        expect(one.data.map((event) => event.version), [1, 2]);
        final all =
            await CqrsTestRuntime(
              eventStore: database,
            ).logReader(0).scan().toList();
        expect(all.map((event) => event.streamPath), [
          'one',
          'two',
          'one',
          'two',
          'one',
        ]);
        expect(all.map((event) => event.position), [0, 1, 2, 3, 4]);
        expect(
          (await database.getStoredCommand(
            CommandId('actor-1', 2),
          ))!.events.length,
          2,
        );
      });

      test('bundle event order defines stored indexes', () async {
        final bundle = _bundle(CommandId('actor-1', 1), ['one', 'two']);
        final reordered = StoredCommand(
          commandId: bundle.commandId,
          dependency: bundle.dependency,
          occuredAt: bundle.occuredAt,
          events: [bundle.events.last, bundle.events.first],
        );
        expect(await database.addStoredCommand(reordered), isTrue);
        expect(
          (await database.getStoredCommand(CommandId('actor-1', 1)))!.toJson(),
          reordered.toJson(),
        );
        final logged = (await database.getLogEvents(0)).data;
        expect(logged.map((event) => event.eventId), [
          EventId('actor-1', 1, 0),
          EventId('actor-1', 1, 1),
        ]);
        expect(logged.map((event) => event.streamPath), ['two', 'one']);
      });
    });
  }
}

StoredCommand _bundle(CommandId id, List<String> paths) {
  final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return StoredCommand(
    commandId: id,
    dependency: CommandDependency(),
    occuredAt: time,
    events: [
      for (final (index, path) in paths.indexed)
        StoredCommandEvent(
          streamPath: path,
          encodedEvent: EncodedEvent(
            kind: 'test',
            bytes: Uint8List.fromList([index]),
          ),
          occuredAt: time,
        ),
    ],
  );
}
