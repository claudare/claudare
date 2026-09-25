import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('bundle contract - ${backend.name}', () {
      late EventStoreTestSession session;
      late EventStore store;
      late CqrsTestRuntime runtime;

      setUp(() async {
        session = await backend.open();
        store = session.store;
        runtime = CqrsTestRuntime(eventStore: store);
      });
      tearDown(() => session.close());

      test('saves and reads a complete bundle', () async {
        final bundle = _bundle(
          CommandId('actor-1', 1),
          paths: ['one', 'two', 'one'],
        );
        expect(
          await store.getStoredCommand(
            CommandId('actor-1', bundle.commandId.sequence),
          ),
          isNull,
        );
        expect(await store.addStoredCommand(bundle), isTrue);

        final restored = await store.getStoredCommand(
          CommandId('actor-1', bundle.commandId.sequence),
        );
        expect(restored, isNotNull);
        expect(restored!.toJson(), bundle.toJson());
        expect(restored.events, isNotEmpty);
        final logged = await runtime.logReader(0).scan().toList();
        expect(logged.map((event) => event.eventId), [
          EventId('actor-1', 1, 0),
          EventId('actor-1', 1, 1),
          EventId('actor-1', 1, 2),
        ]);
        expect(await store.getStreamVersion('one'), isNotNull);
        expect(
          (await session.store.getState()).logVersion,
          CommandDependency({'actor-1': 1}),
        );
      });

      test('returns false for missing dependencies or sequence gaps', () async {
        final gap = _bundle(CommandId('actor-1', 2));
        final dependency = _bundle(
          CommandId('actor-2', 1),
          dependency: CommandDependency({'actor-1': 1}),
        );
        expect(await store.addStoredCommand(gap), isFalse);
        expect(await store.addStoredCommand(dependency), isFalse);
        expect(
          await store.getStoredCommand(
            CommandId('actor-1', gap.commandId.sequence),
          ),
          isNull,
        );
        expect((await session.store.getStatistics()).eventCount, 0);

        expect(
          await store.addStoredCommand(_bundle(CommandId('actor-1', 1))),
          isTrue,
        );
        expect(await store.addStoredCommand(gap), isTrue);
        expect(await store.addStoredCommand(dependency), isTrue);
        expect(
          (await session.store.getState()).logVersion,
          CommandDependency({'actor-1': 2, 'actor-2': 1}),
        );
      });

      test('rejects commands without events without writing', () async {
        final valid = _bundle(CommandId('actor-2', 1));
        final invalid = StoredCommand(
          commandId: valid.commandId,
          dependency: valid.dependency,
          occuredAt: valid.occuredAt,
          events: const [],
        );
        await expectLater(
          Future.sync(() => store.addStoredCommand(invalid)),
          throwsArgumentError,
        );
        expect(
          await store.getStoredCommand(valid.commandId),
          isNull,
        );
      });

      test('keeps log positions and stream versions contiguous', () async {
        await store.addStoredCommand(
          _bundle(CommandId('actor-1', 1), paths: ['one', 'two']),
        );
        await store.addStoredCommand(
          _bundle(CommandId('actor-2', 1), paths: ['one']),
        );
        final events = await runtime.logReader(0).scan().toList();
        expect(events.map((event) => event.position), [0, 1, 2]);
        expect(events.map((event) => event.version), [0, 0, 1]);
      });

      test(
        'local commands preserve stream locks and command sequence',
        () async {
          await store.saveChanges(_changes('one', null));
          await expectLater(
            store.saveChanges(_changes('one', null)),
            throwsA(isA<ConcurrencyProblem>()),
          );
          await store.saveChanges(_changes('one', 0));
          expect(
            (await store.getStoredCommand(CommandId('test-actor', 1)))!.events,
            hasLength(1),
          );
          expect(
            (await store.getStoredCommand(CommandId('test-actor', 2)))!.events,
            hasLength(1),
          );
          expect(
            (await store.getStoredCommand(CommandId('test-actor', 3))),
            isNull,
          );
          expect(await store.getStreamVersion('one'), 1);
        },
      );

      test('reads paged log history with an inclusive cursor', () async {
        for (final actor in ['actor-1', 'actor-2', 'actor-3']) {
          await store.addStoredCommand(_bundle(CommandId(actor, 1)));
        }
        final reader = runtime.logReader(0);
        expect(await reader.loadMore(), isTrue);
        expect(reader.currentPage.map((event) => event.position), [0, 1]);
        expect(await reader.loadMore(), isTrue);
        expect(reader.currentPage.map((event) => event.position), [2]);
        expect(await reader.loadMore(), isFalse);
        final fromTwo = await runtime.logReader(2).scan().toList();
        expect(fromTwo.single.position, 2);
      });

      test('reads one stream from an inclusive version', () async {
        await store.addStoredCommand(
          _bundle(CommandId('actor-1', 1), paths: ['one', 'two']),
        );
        await store.addStoredCommand(
          _bundle(CommandId('actor-1', 2), paths: ['one']),
        );
        final events =
            await runtime.streamReader('one', fromVersion: 1).scan().toList();
        expect(events.single.version, 1);
        expect(events.single.eventId.commandId, CommandId('actor-1', 2));
      });
    });
  }
}

CommandChanges _changes(String path, int? version) => CommandChanges(
  actor: 'test-actor',
  dependency: CommandDependency(),
  occuredAt: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
  locks: [StreamLock(streamPath: path, originatingStreamVersion: version)],
  events: [
    EventAppend(
      streamPath: path,
      encodedEvent: EncodedEvent(kind: 'local', bytes: Uint8List(0)),
      occuredAt: DateTime.fromMillisecondsSinceEpoch(300, isUtc: true),
    ),
  ],
);

StoredCommand _bundle(
  CommandId id, {
  List<String> paths = const ['one'],
  CommandDependency? dependency,
}) {
  final time = DateTime.fromMillisecondsSinceEpoch(300, isUtc: true);
  return StoredCommand(
    commandId: id,
    dependency: dependency ?? CommandDependency(),
    occuredAt: time,
    events: [
      for (final (index, path) in paths.indexed)
        StoredCommandEvent(
          streamPath: path,
          encodedEvent: EncodedEvent(
            kind: 'event-$index',
            bytes: Uint8List.fromList([index]),
          ),
          occuredAt: time,
        ),
    ],
  );
}
