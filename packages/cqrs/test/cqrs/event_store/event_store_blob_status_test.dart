import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} blob metadata', () {
      late EventStore store;

      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
      });

      test('unreferenced blobs have no status', () async {
        expect(await store.getBlobStatus('missing'), isNull);
      });

      for (final origin in ChangeOrigin.values) {
        test('$origin saves the initial availability', () async {
          await _save(store, origin, ['blob']);

          expect(
            await store.getBlobStatus('blob'),
            origin == ChangeOrigin.local
                ? BlobStatus.available
                : BlobStatus.pending,
          );
        });

        test(
          '$origin rejects repeated IDs within a command atomically',
          () async {
            await expectLater(
              _save(store, origin, ['duplicate', 'duplicate']),
              throwsStateError,
            );

            expect(await store.getBlobStatus('duplicate'), isNull);
            expect((await store.getState()).lastCommandLogPosition, isNull);
            expect(await store.getStreamVersion('stream'), isNull);
            await _save(store, ChangeOrigin.remote, ['after']);
            expect((await store.getPendingBlobIds(0)).next, 1);
          },
        );

        for (final available in [false, true]) {
          test(
            '$origin rejects an owned ID with available=$available',
            () async {
              await _save(store, ChangeOrigin.remote, ['owned']);
              if (available) await store.markBlobAvailable('owned');

              await expectLater(
                _save(store, origin, ['new', 'owned'], actor: 'other'),
                throwsStateError,
              );

              expect(await store.getBlobStatus('new'), isNull);
              expect(
                await store.getStoredCommand(const CommandId('other', 1)),
                isNull,
              );
              expect(await store.getStreamVersion('stream'), 0);
              expect(
                await store.getBlobStatus('owned'),
                available ? BlobStatus.available : BlobStatus.pending,
              );
              expect(
                (await store.getStoredCommand(const CommandId('actor', 1)))!
                    .blobIds,
                ['owned'],
              );
            },
          );
        }
      }

      test('local references are excluded from pending work', () async {
        await _save(store, ChangeOrigin.local, ['local']);

        final page = await store.getPendingBlobIds(0);
        expect(page.data, isEmpty);
        expect(page.next, isNull);
      });

      test('marking a blob available removes its pending work', () async {
        await _save(store, ChangeOrigin.remote, ['blob']);

        await store.markBlobAvailable('blob');

        expect(await store.getBlobStatus('blob'), BlobStatus.available);
        expect((await store.getPendingBlobIds(0)).data, isEmpty);
      });

      test('marking an available blob again succeeds', () async {
        await _save(store, ChangeOrigin.remote, ['blob']);
        await store.markBlobAvailable('blob');

        await store.markBlobAvailable('blob');

        expect(await store.getBlobStatus('blob'), BlobStatus.available);
      });

      test(
        'marking an unreferenced blob fails without registering it',
        () async {
          await expectLater(
            store.markBlobAvailable('missing'),
            throwsStateError,
          );

          expect(await store.getBlobStatus('missing'), isNull);
        },
      );

      test('empty pending pages end the scan', () async {
        final page = await store.getPendingBlobIds(0);

        expect(page.data, isEmpty);
        expect(page.next, isNull);
      });

      test('pending cursors cannot be negative', () async {
        await expectLater(store.getPendingBlobIds(-1), throwsArgumentError);
      });

      test('pages preserve command arrival and registration order', () async {
        await _save(store, ChangeOrigin.remote, [
          'second',
          'first',
        ], actor: 'z');
        await _save(store, ChangeOrigin.remote, ['third'], actor: 'a');

        final first = await store.getPendingBlobIds(0);
        expect(first.data, ['second', 'first']);
        expect(first.next, 2);
        final second = await store.getPendingBlobIds(first.next!);
        expect(second.data, ['third']);
        expect(second.next, 3);
        final end = await store.getPendingBlobIds(second.next!);
        expect(end.data, isEmpty);
        expect(end.next, isNull);
      });

      test('pending cursors include the supplied position', () async {
        await _save(store, ChangeOrigin.remote, ['first', 'second', 'third']);

        final page = await store.getPendingBlobIds(1);

        expect(page.data, ['second', 'third']);
        expect(page.next, 3);
      });

      test('pages fill across available positions', () async {
        await _save(store, ChangeOrigin.local, ['local']);
        await _save(store, ChangeOrigin.remote, [
          'first',
          'available',
          'last',
        ], actor: 'remote');
        await store.markBlobAvailable('available');

        final page = await store.getPendingBlobIds(0);

        expect(page.data, ['first', 'last']);
        expect(page.next, 4);
      });

      test('availability changes do not shift a saved cursor', () async {
        await _save(store, ChangeOrigin.remote, ['first', 'second', 'third']);
        final first = await store.getPendingBlobIds(0);
        await store.markBlobAvailable('first');
        await store.markBlobAvailable('second');

        final next = await store.getPendingBlobIds(first.next!);

        expect(next.data, ['third']);
        expect(next.next, 3);
      });

      test('a new scan revisits earlier pending IDs', () async {
        await _save(store, ChangeOrigin.remote, ['retry', 'second', 'third']);
        final reader = PaginatedReader(store.getPendingBlobIds);
        await for (final id in reader.scan()) {
          if (id != 'retry') await store.markBlobAvailable(id);
        }

        expect(await PaginatedReader(store.getPendingBlobIds).scan().toList(), [
          'retry',
        ]);
      });

      for (final available in [false, true]) {
        test('repeated delivery preserves availability=$available', () async {
          final command = _command(['blob']);
          expect(await store.addStoredCommand(command), isTrue);
          if (available) await store.markBlobAvailable('blob');

          expect(await store.addStoredCommand(command), isFalse);

          expect(
            await store.getBlobStatus('blob'),
            available ? BlobStatus.available : BlobStatus.pending,
          );
          expect(
            await PaginatedReader(store.getPendingBlobIds).scan().toList(),
            available ? isEmpty : ['blob'],
          );
        });
      }

      test('rejected remote commands do not register blob metadata', () async {
        final command = _command(['rejected'], sequence: 2);

        expect(await store.addStoredCommand(command), isFalse);

        expect(await store.getBlobStatus('rejected'), isNull);
        expect((await store.getPendingBlobIds(0)).data, isEmpty);
      });

      test('stale local commands do not register blob metadata', () async {
        await _save(store, ChangeOrigin.local, ['committed']);
        final changes = _changes(['rejected'], version: null);

        await expectLater(
          store.saveChanges(changes),
          throwsA(isA<ConcurrencyProblem>()),
        );

        expect(await store.getBlobStatus('rejected'), isNull);
        expect(await store.getBlobStatus('committed'), BlobStatus.available);
      });
    });
  }
}

Future<void> _save(
  EventStore store,
  ChangeOrigin origin,
  List<String> blobs, {
  String actor = 'actor',
}) async {
  if (origin == ChangeOrigin.local) {
    await store.saveChanges(
      _changes(
        blobs,
        actor: actor,
        version: await store.getStreamVersion('stream'),
      ),
    );
  } else {
    expect(await store.addStoredCommand(_command(blobs, actor: actor)), isTrue);
  }
}

CommandChanges _changes(
  List<String> blobs, {
  String actor = 'actor',
  int? version,
}) => CommandChanges(
  actor: actor,
  dependency: CommandDependency(),
  occuredAt: DateTime.utc(2026),
  locks: [StreamLock(streamPath: 'stream', originatingStreamVersion: version)],
  events: [
    EventAppend(
      streamPath: 'stream',
      encodedEvent: EncodedEvent(kind: 'event', bytes: Uint8List(0)),
      occuredAt: DateTime.utc(2026),
    ),
  ],
  blobs: blobs,
);

StoredCommand _command(
  List<String> blobs, {
  String actor = 'actor',
  int sequence = 1,
}) => StoredCommand(
  commandId: CommandId(actor, sequence),
  dependency: CommandDependency(),
  occuredAt: DateTime.utc(2026),
  events: [
    StoredCommandEvent(
      streamPath: 'stream',
      encodedEvent: EncodedEvent(kind: 'event', bytes: Uint8List(0)),
      occuredAt: DateTime.utc(2026),
    ),
  ],
  blobIds: blobs,
);
