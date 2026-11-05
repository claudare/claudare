import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} stream deletion', () {
      late EventStoreTestSession session;
      late EventStore store;

      setUp(() async {
        session = await backend.open();
        store = session.store;
      });
      tearDown(() => session.close());

      test(
        'retains its marker and permanently erases application payloads',
        () async {
          expect(await store.addStoredCommand(_event('actor', 1)), isTrue);
          expect(await store.addStoredCommand(_deleted('other', 1)), isTrue);

          final info = await store.getStreamInfo('one');
          expect(info?.isDeleted, isTrue);
          expect(info?.version, 1);

          final all = await store.getStreamEvents('one', 0);
          expect(all.data.map((event) => event.encodedEvent.kind), [
            SystemEventKinds.eventErased,
            SystemEventKinds.streamDeleted,
          ]);
        },
      );

      test('erases application events received after deletion', () async {
        expect(await store.addStoredCommand(_event('actor', 1)), isTrue);
        expect(await store.addStoredCommand(_deleted('other', 1)), isTrue);
        expect(await store.addStoredCommand(_event('actor', 2)), isTrue);

        final command = await store.getStoredCommand(
          const CommandId('actor', 2),
        );
        expect(
          command?.events.single.encodedEvent.kind,
          SystemEventKinds.eventErased,
        );
      });
    });
  }
}

StoredCommand _event(String actor, int sequence) => StoredCommand(
  commandId: CommandId(actor, sequence),
  dependency: CommandDependency(),
  occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  events: [
    StoredCommandEvent(
      streamPath: 'one',
      encodedEvent: EncodedEvent(kind: 'event', bytes: Uint8List.fromList([1])),
      occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
  ],
);

StoredCommand _deleted(String actor, int sequence) => StoredCommand(
  commandId: CommandId(actor, sequence),
  dependency: CommandDependency(),
  occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  events: [
    StoredCommandEvent(
      streamPath: 'one',
      encodedEvent: EncodedEvent.streamDeleted(),
      occuredAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
  ],
);
