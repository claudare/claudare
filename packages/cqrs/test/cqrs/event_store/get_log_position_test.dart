import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} log position', () {
      late EventStore store;

      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        store = session.store;
      });

      for (final filter in [
        const LogFilter.all(),
        const LogFilter.exact('note/one'),
        const LogFilter.startsWith('note/'),
      ]) {
        test('returns -1 for $filter on an empty store', () async {
          expect(await store.getLogPosition(filter), -1);
        });
      }

      for (final (filter, position) in [
        (const LogFilter.all(), 7),
        (const LogFilter.exact('note/one'), 5),
        (const LogFilter.startsWith('note/'), 6),
        (const LogFilter.startsWith(''), 7),
        (const LogFilter.exact('missing'), -1),
        (const LogFilter.startsWith('missing/'), -1),
        (const LogFilter.startsWith('Note/'), 3),
      ]) {
        test('returns the latest global position for $filter', () async {
          await _appendPaths(store, [
            'note/one',
            'note/one/child',
            'archive/note/one',
            'Note/one',
            'note/two',
            'note/one',
            'note/three',
            'other',
          ]);

          expect(await store.getLogPosition(filter), position);
        });
      }

      for (final (filter, position) in [
        (const LogFilter.startsWith('a%_/'), 1),
        (const LogFilter.exact('a%_/one'), 0),
        (const LogFilter.startsWith("quote'/"), 4),
        (const LogFilter.startsWith('café/'), 6),
      ]) {
        test('matches literal patterns for $filter', () async {
          await _appendPaths(store, [
            'a%_/one',
            'a%_/two',
            'abc/two',
            'a%X/two',
            "quote'/one",
            'quoteX/one',
            'café/one',
            'CAFÉ/one',
          ]);

          expect(await store.getLogPosition(filter), position);
        });
      }

      test('matches empty stream paths exactly', () async {
        await _appendPaths(store, ['', 'other']);

        expect(await store.getLogPosition(const LogFilter.exact('')), 0);
      });

      test('advances after another command adds matching events', () async {
        await _appendPaths(store, ['note/one']);
        expect(
          await store.getLogPosition(const LogFilter.exact('note/one')),
          0,
        );

        await _appendPaths(store, ['other', 'note/one', 'other'], sequence: 2);

        expect(
          await store.getLogPosition(const LogFilter.exact('note/one')),
          2,
        );
      });

      for (final event in [
        EncodedEvent.streamDeleted(),
        EncodedEvent.eventErased(),
      ]) {
        test('includes ${event.kind} records', () async {
          await _appendPaths(store, ['note/one']);
          await _appendPaths(store, ['note/one'], sequence: 2);
          await _appendPaths(store, ['other'], sequence: 3);

          expect(
            await store.getLogPosition(const LogFilter.exact('note/one')),
            1,
          );
        });
      }

      test('includes events from local writes', () async {
        final time = DateTime.utc(2026);
        await store.saveChanges(
          CommandChanges(
            actor: 'local',
            dependency: CommandDependency(),
            occuredAt: time,
            locks: [
              const StreamLock(
                streamPath: 'note/one',
                originatingStreamVersion: -1,
              ),
            ],
            events: [
              for (var index = 0; index < 3; index++)
                EventAppend(
                  streamPath: 'note/one',
                  encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
                  occuredAt: time,
                ),
            ],
          ),
        );

        expect(await store.getLogPosition(const LogFilter.all()), 2);
      });
    });
  }
}

Future<void> _appendPaths(
  EventStore store,
  List<String> paths, {
  int sequence = 1,
}) async {
  final time = DateTime.utc(2026);
  final accepted = await store.addStoredCommand(
    StoredCommand(
      commandId: CommandId('actor', sequence),
      dependency: CommandDependency(),
      occuredAt: time,
      events: [
        for (final path in paths)
          StoredCommandEvent(
            streamPath: path,
            encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
            occuredAt: time,
          ),
      ],
    ),
  );
  expect(accepted, isTrue);
}
