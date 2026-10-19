import 'dart:io';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late IsolateSqlite database;
  late SqliteEventStore store;

  setUp(() async {
    database = IsolateSqlite();
    await database.openInMemory();
    store = SqliteEventStore(database);
    await store.migrate();
  });
  tearDown(() => store.close());

  for (final origin in ChangeOrigin.values) {
    test('$origin persists ordered ownership and availability', () async {
      await _save(store, origin, ['second', 'first']);

      final rows = await database.query('''SELECT
        log_position, blob_id, id_actor, id_sequence, blob_index, available
        FROM blob ORDER BY log_position;''');

      expect(rows.data, [
        [0, 'second', 'actor', 1, 0, origin == ChangeOrigin.local ? 1 : 0],
        [1, 'first', 'actor', 1, 1, origin == ChangeOrigin.local ? 1 : 0],
      ]);
    });

    test(
      '$origin rolls back history and positions when metadata fails',
      () async {
        await database.execute('''CREATE TRIGGER fail_blob BEFORE INSERT ON blob
        WHEN NEW.blob_index = 1
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END;''');

        await expectLater(
          _save(store, origin, ['first', 'second']),
          throwsA(isA<EventStoreException>()),
        );

        expect((await store.getState()).lastCommandLogPosition, isNull);
        expect(
          (await store.getLogEvents(const LogFilter.all(), 0)).data,
          isEmpty,
        );
        expect(await store.getStreamVersion('stream'), isNull);
        expect(await store.getBlobStatus('first'), isNull);
        await database.execute('DROP TRIGGER fail_blob;');
        await _save(store, origin, ['after-first', 'after-second']);
        final rows = await database.query(
          'SELECT log_position FROM blob ORDER BY log_position;',
        );
        expect(rows.data, [
          [0],
          [1],
        ]);
      },
    );
  }

  test('reopening preserves availability and pending cursors', () async {
    final directory = await Directory.systemTemp.createTemp('blob-metadata-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/events.sqlite';
    final firstDatabase = IsolateSqlite();
    await firstDatabase.open(path);
    addTearDown(firstDatabase.close);
    final first = SqliteEventStore(firstDatabase, eventFetchPageSize: 2);
    await first.migrate();
    await _save(first, ChangeOrigin.remote, ['downloaded', 'pending', 'later']);
    await first.markBlobAvailable('downloaded');
    final before = await first.getPendingBlobIds(0);
    await first.close();

    final secondDatabase = IsolateSqlite();
    await secondDatabase.open(path);
    addTearDown(secondDatabase.close);
    final second = SqliteEventStore(secondDatabase, eventFetchPageSize: 2);
    await second.migrate();

    expect(await second.getBlobStatus('downloaded'), BlobStatus.available);
    expect(await second.getBlobStatus('pending'), BlobStatus.pending);
    final after = await second.getPendingBlobIds(0);
    expect(after.data, before.data);
    expect(after.next, before.next);
    expect(
      (await second.getStoredCommand(const CommandId('actor', 1)))!.blobIds,
      ['downloaded', 'pending', 'later'],
    );
    await _save(second, ChangeOrigin.remote, ['new'], actor: 'other');
    final next = await second.getPendingBlobIds(before.next!);
    expect(next.data, ['new']);
    expect(next.next, 4);
  });
}

Future<void> _save(
  EventStore store,
  ChangeOrigin origin,
  List<String> blobs, {
  String actor = 'actor',
}) async {
  final time = DateTime.utc(2026);
  final event = EncodedEvent(kind: 'event', bytes: Uint8List(0));
  if (origin == ChangeOrigin.local) {
    await store.saveChanges(
      CommandChanges(
        actor: actor,
        dependency: CommandDependency(),
        occuredAt: time,
        locks: const [
          StreamLock(streamPath: 'stream', originatingStreamVersion: null),
        ],
        events: [
          EventAppend(
            streamPath: 'stream',
            encodedEvent: event,
            occuredAt: time,
          ),
        ],
        blobs: blobs,
      ),
    );
  } else {
    expect(
      await store.addStoredCommand(
        StoredCommand(
          commandId: CommandId(actor, 1),
          dependency: CommandDependency(),
          occuredAt: time,
          events: [
            StoredCommandEvent(
              streamPath: 'stream',
              encodedEvent: event,
              occuredAt: time,
            ),
          ],
          blobIds: blobs,
        ),
      ),
      isTrue,
    );
  }
}
