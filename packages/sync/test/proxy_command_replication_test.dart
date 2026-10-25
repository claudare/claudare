import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';
import 'package:transport/transport.dart';

import 'transport/proxy_transport_test_helper.dart';

void main() {
  test('proxy restarts commands while retaining peer connections', () async {
    final proxy = TestProxy();
    final clock = TestClock();
    final a = TestTransport(proxy, clock, 'a');
    final b = TestTransport(proxy, clock, 'b');
    addTearDown(() async {
      await Future.wait([a.close(), b.close()]);
    });
    final stores = [MemoryEventStore(), MemoryEventStore()];
    final replicators = <CommandReplicator>[];
    final running = <Future<void>>[];

    void startReplication(TestTransport transport, MemoryEventStore store) {
      transport.onPeer = (peer) {
        final multiplexer = PeerMultiplexer(peer.channel);
        multiplexer.commandSessions.listen((channel) {
          if (!identical(channel, multiplexer.commands)) return;
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
      };
    }

    startReplication(a, stores[0]);
    startReplication(b, stores[1]);
    final first = command('a', 1);
    expect(await stores[0].addStoredCommand(first), isTrue);
    await Future.wait([a.start(), b.start()]);
    await flushMessages();
    expect(a.peers, hasLength(1));
    expect(b.peers, hasLength(1));
    expect(
      (await stores[1].getStoredCommand(first.commandId))!.toJson(),
      first.toJson(),
    );
    await replicators.first.close();
    await Future.wait(running.take(2));
    await flushMessages();
    expect(replicators, hasLength(4));
    expect(a.peers, hasLength(1));
    expect(b.peers, hasLength(1));
    final second = command('b', 1);
    expect(await stores[1].addStoredCommand(second), isTrue);
    await flushMessages();
    expect(
      (await stores[0].getStoredCommand(second.commandId))!.toJson(),
      second.toJson(),
    );
    await Future.wait([a.close(), b.close()]);
    await Future.wait(running);
    expect(clock.activeTimers, 0);
  });
}

StoredCommand command(String actor, int sequence) => StoredCommand(
  blobIds: const [],
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
