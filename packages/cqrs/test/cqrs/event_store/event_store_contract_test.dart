import 'dart:typed_data';

import 'package:common/common.dart';
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

      setUp(() async {
        session = await backend.open();
        store = session.store;
      });
      tearDown(() => session.close());

      test('saves and reads a complete bundle', () async {
        final bundle = _bundle(CommandId(3, 1), paths: ['one', 'two', 'one']);
        expect(await store.getBundle(bundle.commandId), isNull);
        expect(await store.saveBundle(bundle), isTrue);

        final restored = await store.getBundle(bundle.commandId);
        expect(restored, isNotNull);
        expect(restored, bundle);
        expect(restored!.isValid, isTrue);
        final logged = await store.getLogEventReader(0).scan().toList();
        expect(logged.map((event) => event.eventId), [
          EventId(3, 1, 0),
          EventId(3, 1, 1),
          EventId(3, 1, 2),
        ]);
        expect(await store.getStreamInfo('one'), isNotNull);
        expect(
          (await session.database.getState()).logVersion,
          VersionVector({3: 1}),
        );
      });

      test('returns false for missing dependencies or sequence gaps', () async {
        final gap = _bundle(CommandId(3, 2));
        final dependency = _bundle(
          CommandId(4, 1),
          dependency: VersionVector({3: 1}),
        );
        expect(await store.saveBundle(gap), isFalse);
        expect(await store.saveBundle(dependency), isFalse);
        expect(await store.getBundle(gap.commandId), isNull);
        expect((await session.database.getStatistics()).eventCount, 0);

        expect(await store.saveBundle(_bundle(CommandId(3, 1))), isTrue);
        expect(await store.saveBundle(gap), isTrue);
        expect(await store.saveBundle(dependency), isTrue);
        expect(
          (await session.database.getState()).logVersion,
          VersionVector({3: 2, 4: 1}),
        );
      });

      test('rejects incomplete bundles without writing', () async {
        final valid = _bundle(CommandId(2, 1));
        final invalid = CommandBundle(
          commandId: valid.commandId,
          dependency: valid.dependency,
          occuredAt: valid.occuredAt,
          events: const [],
        );
        await expectLater(
          Future.sync(() => store.saveBundle(invalid)),
          throwsArgumentError,
        );
        expect(await store.getBundle(valid.commandId), isNull);
      });

      test('keeps log positions and stream versions contiguous', () async {
        await store.saveBundle(_bundle(CommandId(2, 1), paths: ['one', 'two']));
        await store.saveBundle(_bundle(CommandId(4, 1), paths: ['one']));
        final events = await store.getLogEventReader(0).scan().toList();
        expect(events.map((event) => event.logPosition), [0, 1, 2]);
        expect(events.map((event) => event.version), [0, 0, 1]);
      });

      test('signals only after a bundle is saved', () async {
        var signals = 0;
        final subscription = store.logChanges.listen((_) => signals++);
        addTearDown(subscription.cancel);
        expect(await store.saveBundle(_bundle(CommandId(2, 2))), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(signals, 0);
        expect(await store.saveBundle(_bundle(CommandId(2, 1))), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(signals, 1);
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
            (await store.getBundle(CommandId(0, 1)))!.events,
            hasLength(1),
          );
          expect(
            (await store.getBundle(CommandId(0, 2)))!.events,
            hasLength(1),
          );
          expect((await store.getBundle(CommandId(0, 3))), isNull);
          expect(
            (await store.getStreamInfo('one'))!.originatingStreamVersion,
            1,
          );
        },
      );

      test('reads paged log history with an inclusive cursor', () async {
        for (final device in [1, 2, 3]) {
          await store.saveBundle(_bundle(CommandId(device, 1)));
        }
        final reader = store.getLogEventReader(0);
        expect(await reader.loadMore(), isTrue);
        expect(reader.currentPage.map((event) => event.logPosition), [0, 1]);
        expect(await reader.loadMore(), isTrue);
        expect(reader.currentPage.map((event) => event.logPosition), [2]);
        expect(await reader.loadMore(), isFalse);
        final fromTwo = await store.getLogEventReader(2).scan().toList();
        expect(fromTwo.single.logPosition, 2);
      });

      test('reads one stream from an inclusive version', () async {
        await store.saveBundle(_bundle(CommandId(1, 1), paths: ['one', 'two']));
        await store.saveBundle(_bundle(CommandId(1, 2), paths: ['one']));
        final events =
            await store.getStreamReader('one', fromVersion: 1).scan().toList();
        expect(events.single.version, 1);
        expect(events.single.eventId.commandId, CommandId(1, 2));
      });
    });
  }
}

CommandChanges _changes(String path, int? version) => CommandChanges(
  dependency: VersionVector(),
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

CommandBundle _bundle(
  CommandId id, {
  List<String> paths = const ['one'],
  VersionVector? dependency,
}) {
  final time = DateTime.fromMillisecondsSinceEpoch(300, isUtc: true);
  return CommandBundle(
    commandId: id,
    dependency: dependency ?? VersionVector(),
    occuredAt: time,
    events: [
      for (final (index, path) in paths.indexed)
        BundledEvent(
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
