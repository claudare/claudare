import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

void main() {
  test('command replication discovers metadata and pulls bytes', () async {
    final firstEvents = MemoryEventStore(eventFetchPageSize: 1);
    final secondEvents = MemoryEventStore(eventFetchPageSize: 1);
    final firstBlobs = MemoryBlobStore();
    final secondBlobs = MemoryBlobStore();
    final commands = InMemoryCommandReplication(
      store1: firstEvents,
      store2: secondEvents,
      logger: const NoopLogger(),
    );
    final commandRun = commands.run();
    final channel = StreamChannelController<BlobReplicationMessage>();
    final workers = [
      BlobReplicator(
        channel: channel.local,
        eventStore: firstEvents,
        blobStore: firstBlobs,
        logger: const NoopLogger(),
      ),
      BlobReplicator(
        channel: channel.foreign,
        eventStore: secondEvents,
        blobStore: secondBlobs,
        logger: const NoopLogger(),
      ),
    ];
    final runs = workers.map((worker) => worker.run()).toList();
    addTearDown(() async {
      await commands.close();
      await commandRun;
      await Future.wait(workers.map((worker) => worker.close()));
      await Future.wait(runs);
    });
    await firstBlobs.save('id', Uint8List.fromList([1, 2]));
    await firstEvents.addStoredCommand(
      StoredCommand(
        commandId: const CommandId('id', 1),
        dependency: CommandDependency(),
        occuredAt: DateTime.utc(2026),
        events: [
          StoredCommandEvent(
            streamPath: '_blob/id',
            encodedEvent: EncodedEvent(
              kind: 'blob.created',
              bytes: Uint8List(0),
            ),
            occuredAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(await secondBlobs.get('id'), [1, 2]);
  });
}
