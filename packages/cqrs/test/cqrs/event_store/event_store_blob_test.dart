import 'dart:typed_data';

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

      test('persists ordered local blob references', () async {
        await store.saveChanges(_changes(['second', 'first']));
        final command = await store.getStoredCommand(
          const CommandId('actor', 1),
        );
        expect(command!.blobIds, ['second', 'first']);
      });

      test('snapshots reference lists during local save', () async {
        final ids = ['second', 'first'];
        await store.saveChanges(_changes(ids));
        ids.clear();
        final command = await store.getStoredCommand(
          const CommandId('actor', 1),
        );
        expect(command!.blobIds, ['second', 'first']);
      });

      test(
        'preserves remote references without requiring blob bytes',
        () async {
          final changes = _changes(['second', 'first']);
          final command = StoredCommand(
            commandId: const CommandId('remote', 1),
            dependency: CommandDependency(),
            occuredAt: changes.occuredAt,
            blobIds: changes.blobs,
            events: [
              for (final event in changes.events)
                StoredCommandEvent(
                  streamPath: event.streamPath,
                  encodedEvent: event.encodedEvent,
                  occuredAt: event.occuredAt,
                ),
            ],
          );
          expect(await store.addStoredCommand(command), isTrue);
          expect((await store.getStoredCommand(command.commandId))!.blobIds, [
            'second',
            'first',
          ]);
        },
      );

      test('concurrency failure does not commit blob references', () async {
        await store.saveChanges(_changes(['committed']));
        await expectLater(
          store.saveChanges(_changes(['abandoned'])),
          throwsA(isA<ConcurrencyProblem>()),
        );
        expect(
          await store.getStoredCommand(const CommandId('actor', 2)),
          isNull,
        );
        expect(
          (await store.getStoredCommand(const CommandId('actor', 1)))!.blobIds,
          ['committed'],
        );
      });
    });
  }
}

CommandChanges _changes(List<String> blobs) => CommandChanges(
  actor: 'actor',
  dependency: CommandDependency(),
  occuredAt: DateTime.utc(2026),
  locks: const [
    StreamLock(streamPath: 'stream', originatingStreamVersion: null),
  ],
  events: [
    EventAppend(
      streamPath: 'stream',
      encodedEvent: EncodedEvent(kind: 'event', bytes: Uint8List(0)),
      occuredAt: DateTime.utc(2026),
    ),
  ],
  blobs: blobs,
);
