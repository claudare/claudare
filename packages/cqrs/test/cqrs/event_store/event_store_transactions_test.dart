import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group(backend.name, () {
      late EventStore store;
      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
      });

      test('reports empty state', () async {
        final state = await store.getState();
        expect(state.lastCommandLogPosition, isNull);
        expect(state.lastEventLogPosition, isNull);
        expect(state.logVersion, CommandDependency());
        expect(await store.getStreamVersion('missing'), isNull);
      });

      test('counts stored events and payload bytes', () async {
        await store.saveChanges(_changes('one', count: 3));
        final statistics = await store.getStatistics();
        expect(statistics.eventCount, 3);
        expect(statistics.storageSize, 6);
      });

      test('empty changes do not allocate a command', () async {
        await store.saveChanges(_changes('one', count: 0));
        expect((await store.getState()).lastCommandLogPosition, isNull);
        await store.saveChanges(_changes('one'));
        expect(
          await store.getStoredCommand(CommandId('test-actor', 1)),
          isNotNull,
        );
      });

      test(
        'rejects changes with missing dependencies before writing',
        () async {
          await expectLater(
            store.saveChanges(
              _changes('one', dependency: CommandDependency({'actor-7': 1})),
            ),
            throwsStateError,
          );
          expect((await store.getState()).lastEventLogPosition, isNull);
          expect(await store.getStreamVersion('one'), isNull);
        },
      );

      test('rejects changes without stream locks before writing', () async {
        final changes = _changes('one');
        await expectLater(
          store.saveChanges(
            CommandChanges(
              actor: 'test-actor',
              dependency: changes.dependency,
              occuredAt: changes.occuredAt,
              locks: [],
              events: changes.events,
            ),
          ),
          throwsArgumentError,
        );
        expect((await store.getState()).lastCommandLogPosition, isNull);
      });

      test('concurrent stale-lock writes have one winner', () async {
        Future<bool> save() async {
          try {
            await store.saveChanges(_changes('one', count: 3));
            return true;
          } on ConcurrencyProblem {
            return false;
          }
        }

        final results = await Future.wait([save(), save()]);
        expect(results.where((saved) => saved), hasLength(1));
        expect((await store.getStatistics()).eventCount, 3);
        expect((await store.getState()).lastCommandLogPosition, 0);
        await store.saveChanges(_changes('one', version: 2));
        final state = await store.getState();
        expect(state.lastCommandLogPosition, 1);
        expect(state.lastEventLogPosition, 3);
        expect(state.logVersion, CommandDependency({'test-actor': 2}));
      });

      test(
        'concurrent independent writes allocate distinct command IDs',
        () async {
          await Future.wait([
            for (var i = 0; i < 12; i++)
              store.saveChanges(_changes('stream/$i')),
          ]);
          final state = await store.getState();
          expect(state.logVersion, CommandDependency({'test-actor': 12}));
          expect(state.lastCommandLogPosition, 11);
          expect(state.lastEventLogPosition, 11);
          for (var sequence = 1; sequence <= 12; sequence++) {
            expect(
              await store.getStoredCommand(CommandId('test-actor', sequence)),
              isNotNull,
            );
          }
        },
      );

      test('duplicate bundles leave the log unchanged', () async {
        await store.saveChanges(_changes('one'));
        final bundle =
            (await store.getStoredCommand(CommandId('test-actor', 1)))!;
        expect(await store.addStoredCommand(bundle), isFalse);
        expect((await store.getStatistics()).eventCount, 1);
        expect(
          (await store.getState()).logVersion,
          CommandDependency({'test-actor': 1}),
        );
      });
    });
  }

  for (final pageSize in [null, 1, 3]) {
    for (final backend in [
      MemoryEventStoreTestBackend(eventFetchPageSize: pageSize),
      SqliteEventStoreTestBackend(eventFetchPageSize: pageSize),
    ]) {
      group('${backend.name} page size ${pageSize ?? 'default'}', () {
        late EventStore store;
        setUp(() async {
          final session = await backend.open();
          addTearDown(session.close);
          store = session.store;
          await store.saveChanges(_changes('one', count: 12));
        });

        for (final stream in [false, true]) {
          test(
            'pages ${stream ? 'stream' : 'log'} with inclusive cursors',
            () async {
              final expectedSize = pageSize ?? 10;
              Future<PaginatedResult<StoredEvent>> read(int cursor) =>
                  stream
                      ? store.getStreamEvents('one', cursor)
                      : store.getLogEvents(cursor);
              final first = await read(1);
              expect(first.data, hasLength(expectedSize));
              expect(first.data.first.position, 1);
              expect(first.next, 1 + expectedSize);
              final last = await read(11);
              expect(last.data.single.position, 11);
              expect(last.next, 12);
              final empty = await read(last.next!);
              expect(empty.data, isEmpty);
              expect(empty.next, isNull);
            },
          );
        }
      });
    }
  }

  for (final pageSize in [0, -1]) {
    for (final backend in [
      MemoryEventStoreTestBackend(eventFetchPageSize: pageSize),
      SqliteEventStoreTestBackend(eventFetchPageSize: pageSize),
    ]) {
      test('${backend.name} rejects page size $pageSize', () async {
        await expectLater(backend.open(), throwsArgumentError);
      });
    }
  }
}

CommandChanges _changes(
  String path, {
  int count = 1,
  int? version,
  CommandDependency? dependency,
}) {
  final timestamp = DateTime.utc(2026);
  return CommandChanges(
    actor: 'test-actor',
    dependency: dependency ?? CommandDependency(),
    occuredAt: timestamp,
    locks: [StreamLock(streamPath: path, originatingStreamVersion: version)],
    events: [
      for (var i = 0; i < count; i++)
        EventAppend(
          streamPath: path,
          encodedEvent: EncodedEvent(
            kind: 'event',
            bytes: Uint8List.fromList([1, 2]),
          ),
          occuredAt: timestamp,
        ),
    ],
  );
}
