import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  test('memory backend is ready without initialization', () async {
    final session = await const MemoryEventDatabaseTestBackend().open();
    addTearDown(session.close);
    expect((await session.database.getState()).lastEventLogPosition, null);
    expect((await session.store.getStatistics()).eventCount, 0);
  });

  test('SQLite backend closes its database', () async {
    final session = await const SqliteEventDatabaseTestBackend().open();
    final database = session.database as SqliteEventDatabase;
    await session.close();
    await expectLater(database.getState(), throwsStateError);
  });

  for (final backend in eventStoreTestBackends) {
    group('${backend.name} database', () {
      late EventStoreTestSession session;
      late EventDatabase database;

      setUp(() async {
        session = await backend.open();
        database = session.database;
      });
      tearDown(() => session.close());

      test('reconstructs interleaved stream paths', () async {
        expect(
          await database.saveBundle(
            _bundle(CommandId(1, 1), ['one', 'two', 'one']),
          ),
          isTrue,
        );
        expect(
          await database.saveBundle(_bundle(CommandId(1, 2), ['two', 'one'])),
          isTrue,
        );

        expect(await database.getStreamVersion('one'), 2);
        expect(await database.getStreamVersion('two'), 1);
        final one = await database.getStreamEvents('one', 1, 10);
        expect(one.data.map((event) => event.version), [1, 2]);
        final all = await database.getLogEvents(0, 10);
        expect(all.data.map((event) => event.streamPath), [
          'one',
          'two',
          'one',
          'two',
          'one',
        ]);
        expect(all.data.map((event) => event.logPosition), [0, 1, 2, 3, 4]);
        expect((await database.getBundle(CommandId(1, 2)))!.events.length, 2);
      });

      test('bundle event order defines stored indexes', () async {
        final bundle = _bundle(CommandId(1, 1), ['one', 'two']);
        final reordered = CommandBundle(
          commandId: bundle.commandId,
          dependency: bundle.dependency,
          occuredAt: bundle.occuredAt,
          events: [bundle.events.last, bundle.events.first],
        );
        expect(await database.saveBundle(reordered), isTrue);
        expect(await database.getBundle(CommandId(1, 1)), reordered);
        final logged = (await database.getLogEvents(0, 10)).data;
        expect(logged.map((event) => event.eventId), [
          EventId(1, 1, 0),
          EventId(1, 1, 1),
        ]);
        expect(logged.map((event) => event.streamPath), ['two', 'one']);
      });
    });
  }
}

CommandBundle _bundle(CommandId id, List<String> paths) {
  final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return CommandBundle(
    commandId: id,
    dependency: VersionVector(),
    occuredAt: time,
    events: [
      for (final (index, path) in paths.indexed)
        BundledEvent(
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
