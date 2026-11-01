import 'dart:async';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

Future<void> seed(EventStore store, String id) async {
  await store.addStoredCommand(
    StoredCommand(
      commandId: CommandId(id, 1),
      dependency: CommandDependency(),
      occuredAt: DateTime.utc(2026),
      events: [
        StoredCommandEvent(
          streamPath: '_blob/$id',
          encodedEvent: EncodedEvent(kind: 'blob.created', bytes: Uint8List(0)),
          occuredAt: DateTime.utc(2026),
        ),
      ],
    ),
  );
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class Harness {
  final events = MemoryEventStore(eventFetchPageSize: 1);
  final MemoryBlobStore blobs;
  Harness({MemoryBlobStore? blobs}) : blobs = blobs ?? MemoryBlobStore();
  final channel = StreamChannelController<BlobReplicationMessage>();
  final messages = <BlobReplicationMessage>[];
  late final worker = BlobReplicator(
    channel: channel.local,
    eventStore: events,
    blobStore: blobs,
    logger: const NoopLogger(),
  );

  void start() {
    final subscription = channel.foreign.stream.listen(messages.add);
    final running = worker.run();
    addTearDown(() async {
      await worker.close();
      await running;
      await subscription.cancel();
    });
  }

  void send(BlobReplicationMessage message) =>
      channel.foreign.sink.add(message);
}

void main() {
  test(
    'retired session finishes persistence without announcing bytes',
    () async {
      final blobs = _GatedStore();
      final h = Harness(blobs: blobs);
      await seed(h.events, 'id');
      h.start();
      await flush();
      h.send(
        BlobReplicationMessageData(
          blobId: 'id',
          bytes: Uint8List.fromList([9]),
        ),
      );
      await blobs.started.future;
      final closing = h.worker.close();
      blobs.release.complete();
      await closing;
      await flush();
      expect(await blobs.get('id'), [9]);
      expect(h.messages.whereType<BlobReplicationMessageAvailable>(), isEmpty);
    },
  );

  test('unsolicited responses fail the session', () async {
    final h = Harness();
    final subscription = h.channel.foreign.stream.listen((_) {});
    addTearDown(subscription.cancel);
    final failure = expectLater(
      h.worker.run(),
      throwsA(isA<BlobReplicationException>()),
    );
    h.send(const BlobReplicationMessageMissing(blobId: 'unknown'));
    await failure;
    await h.worker.close();
  });

  const codec = BlobReplicationMessageCodec();
  for (final message in <BlobReplicationMessage>[
    const BlobReplicationMessageRequest(blobId: 'id'),
    const BlobReplicationMessageAvailable(blobId: 'id'),
    const BlobReplicationMessageMissing(blobId: 'id'),
    BlobReplicationMessageData(
      blobId: 'id',
      bytes: Uint8List.fromList([0, 255]),
    ),
  ]) {
    test('${message.runtimeType} round trip', () {
      expect(codec.decode(codec.encode(message)).toJson(), message.toJson());
    });
  }
  for (final invalid in [
    '[]',
    '{}',
    '{"type":"data","blobId":"id","bytes":"!"}',
  ]) {
    test('rejects malformed message $invalid', () {
      expect(() => codec.decode(invalid), throwsFormatException);
    });
  }

  test('scans all pages and skips locally available bytes', () async {
    final h = Harness();
    await seed(h.events, 'local');
    await seed(h.events, 'remote');
    await h.blobs.save('local', Uint8List(0));
    h.start();
    await flush();
    expect(
      h.messages.whereType<BlobReplicationMessageRequest>().map(
        (m) => m.blobId,
      ),
      ['remote'],
    );
  });

  test('missing waits for a later availability notification', () async {
    final h = Harness()..start();
    await seed(h.events, 'id');
    await flush();
    h.send(const BlobReplicationMessageMissing(blobId: 'id'));
    await flush();
    expect(h.messages.whereType<BlobReplicationMessageRequest>(), hasLength(1));
    h.send(const BlobReplicationMessageAvailable(blobId: 'id'));
    await flush();
    expect(h.messages.whereType<BlobReplicationMessageRequest>(), hasLength(2));
  });

  test('availability during a pending request survives missing', () async {
    final h = Harness();
    await seed(h.events, 'id');
    h.start();
    await flush();
    h.send(const BlobReplicationMessageAvailable(blobId: 'id'));
    h.send(const BlobReplicationMessageMissing(blobId: 'id'));
    await flush();
    expect(h.messages.whereType<BlobReplicationMessageRequest>(), hasLength(2));
    h.send(const BlobReplicationMessageMissing(blobId: 'id'));
    await flush();
    expect(h.messages.whereType<BlobReplicationMessageRequest>(), hasLength(2));
  });

  test('availability before metadata waits for command discovery', () async {
    final h = Harness()..start();
    h.send(const BlobReplicationMessageAvailable(blobId: 'id'));
    await flush();
    expect(h.messages, isEmpty);
    await seed(h.events, 'id');
    await flush();
    expect(h.messages.single, isA<BlobReplicationMessageRequest>());
  });

  test('saving downloaded bytes announces availability', () async {
    final h = Harness();
    await seed(h.events, 'id');
    h.start();
    await flush();
    h.send(
      BlobReplicationMessageData(blobId: 'id', bytes: Uint8List.fromList([7])),
    );
    await flush();
    expect(await h.blobs.get('id'), [7]);
    expect(
      h.messages.whereType<BlobReplicationMessageAvailable>().single.blobId,
      'id',
    );
  });

  test('serves requests while waiting for a response', () async {
    final h = Harness();
    await seed(h.events, 'pending');
    await h.blobs.save('local', Uint8List(0));
    h.start();
    await flush();
    h.send(const BlobReplicationMessageRequest(blobId: 'local'));
    h.send(const BlobReplicationMessageRequest(blobId: 'absent'));
    await flush();
    expect(
      h.messages.whereType<BlobReplicationMessageData>().single.bytes,
      isEmpty,
    );
    expect(
      h.messages.whereType<BlobReplicationMessageMissing>().single.blobId,
      'absent',
    );
  });

  test('command replication discovers metadata and pulls bytes', () async {
    final first = Harness();
    final second = Harness();
    final commands = InMemoryCommandReplication(
      store1: first.events,
      store2: second.events,
      logger: const NoopLogger(),
    );
    final commandRun = commands.run();
    final channel = StreamChannelController<BlobReplicationMessage>();
    final workers = [
      BlobReplicator(
        channel: channel.local,
        eventStore: first.events,
        blobStore: first.blobs,
        logger: const NoopLogger(),
      ),
      BlobReplicator(
        channel: channel.foreign,
        eventStore: second.events,
        blobStore: second.blobs,
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
    await first.blobs.save('id', Uint8List.fromList([1, 2]));
    await seed(first.events, 'id');
    await flush();
    expect(await second.blobs.get('id'), [1, 2]);
  });
}

class _GatedStore extends MemoryBlobStore {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> save(String id, Uint8List bytes) async {
    started.complete();
    await release.future;
    await super.save(id, bytes);
  }
}
