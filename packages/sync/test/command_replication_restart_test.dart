import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';
import 'package:transport/transport.dart';
import 'package:transport_test/transport_test.dart';

import 'sync_test_utils.dart';

void main() {
  test('memory transport retains peers when commands restart', () async {
    final network = MemoryTransportNetwork();
    final a = network.createTransport(actor: 'a');
    final b = network.createTransport(actor: 'b');
    addTearDown(() async {
      await Future.wait([a.close(), b.close()]);
    });
    final aPeers = <PeerTransport>[];
    final bPeers = <PeerTransport>[];
    final stores = [MemoryEventStore(), MemoryEventStore()];
    final replicators = <CommandReplicator>[];
    final running = <Future<void>>[];

    void startReplication(
      MemoryTransport transport,
      MemoryEventStore store,
      List<PeerTransport> peers,
    ) {
      transport.peerTransports.listen((peer) {
        peers.add(peer);
        final multiplexer = PeerMultiplexer(peer.channel);
        multiplexer.sessions('commands').listen((channel) {
          if (!identical(channel, multiplexer.channel('commands'))) return;
          final replicator = CommandReplicator(
            channel: channel.transform(
              StreamChannelTransformer.fromCodec(
                const CommandReplicationMessageCodec(),
              ),
            ),
            eventStore: store,
            logger: const NoopLogger(),
          );
          replicators.add(replicator);
          running.add(replicator.run());
        });
      });
    }

    startReplication(a, stores[0], aPeers);
    startReplication(b, stores[1], bPeers);
    final first = command('a', 1);
    expect(await stores[0].addStoredCommand(first), isTrue);
    await Future.wait([a.start(), b.start()]);
    await flushMessages();
    expect(aPeers, hasLength(1));
    expect(bPeers, hasLength(1));
    expect(
      (await stores[1].getStoredCommand(first.commandId))!.toJson(),
      first.toJson(),
    );
    await replicators.first.close();
    await Future.wait(running.take(2));
    await flushMessages();
    expect(replicators, hasLength(4));
    expect(aPeers, hasLength(1));
    expect(bPeers, hasLength(1));
    final second = command('b', 1);
    expect(await stores[1].addStoredCommand(second), isTrue);
    await flushMessages();
    expect(
      (await stores[0].getStoredCommand(second.commandId))!.toJson(),
      second.toJson(),
    );
    await Future.wait([a.close(), b.close()]);
    await Future.wait(running);
  });
}

StoredCommand command(String actor, int sequence) => StoredCommand(
  commandId: CommandId(actor, sequence),
  dependency: CommandDependency(),
  occuredAt: DateTime.utc(2026),
  events: [
    StoredCommandEvent(
      streamPath: actor,
      encodedEvent: EncodedEvent(
        kind: 'test',
        bytes: Uint8List.fromList([sequence]),
      ),
      occuredAt: DateTime.utc(2026),
    ),
  ],
);
