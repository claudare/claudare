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

      test('invalid event identity is rejected atomically', () async {
        final bundle = _bundle(CommandId(1, 1), ['one', 'two']);
        final invalid = CommandBundle(
          command: bundle.command,
          events: [bundle.events.last, bundle.events.first],
        );
        await expectLater(
          Future.sync(() => database.saveBundle(invalid)),
          throwsArgumentError,
        );
        expect(await database.getBundle(CommandId(1, 1)), isNull);
        expect((await database.getState()).lastEventLogPosition, isNull);
      });
    });
  }
}

CommandBundle _bundle(CommandId id, List<String> paths) {
  final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return CommandBundle(
    command: StagedCommand(
      commandId: id,
      dependency: VersionVector(),
      occuredAt: time,
      eventCount: paths.length,
    ),
    events: [
      for (final (index, path) in paths.indexed)
        StagedEvent(
          eventId: EventId(id.deviceId, id.sequence, index),
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
