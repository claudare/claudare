import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';

import 'proxy_transport_test_helper.dart';

void main() {
  late TestProxy proxy;
  late TestClock clock;
  late TestTransport a;
  late TestTransport b;

  setUp(() {
    proxy = TestProxy();
    clock = TestClock();
    a = TestTransport(proxy, clock, 'a');
    b = TestTransport(proxy, clock, 'b');
  });

  tearDown(() async {
    await Future.wait([a.close(), b.close()]);
    expect(clock.activeTimers, 0);
  });

  Future<void> connect() async {
    await Future.wait([a.start(), b.start()]);
    await flushMessages();
    expect(a.peers, hasLength(1));
    expect(b.peers, hasLength(1));
  }

  for (final order in ['a first', 'b first', 'simultaneous']) {
    test('discovers exactly one session with $order', () async {
      if (order == 'simultaneous') {
        await connect();
      } else {
        await (order == 'a first' ? a : b).start();
        await flushMessages();
        await (order == 'a first' ? b : a).start();
        await flushMessages();
      }
      await clock.elapse(const Duration(seconds: 30));
      expect(a.peers.map((peer) => peer.actor), ['b']);
      expect(b.peers.map((peer) => peer.actor), ['a']);
      expect(
        proxy.sent
            .where((sent) => sent.message is TransportMessageHandshake)
            .map((sent) => sent.sender)
            .toSet(),
        {'a'},
      );
    });
  }

  test('ignores its own discovery and isolates groups', () async {
    final other = TestTransport(proxy, clock, 'c', group: 'other');
    await a.start();
    await other.start();
    await clock.elapse(const Duration(seconds: 10));
    expect(a.peers, isEmpty);
    expect(other.peers, isEmpty);
    await other.close();
  });

  test('does not resend a handshake while awaiting acknowledgement', () async {
    proxy.drop = (sent) => sent.message is TransportMessageHandshakeAck;
    await Future.wait([a.start(), b.start()]);
    await flushMessages();
    expect(a.peers, isEmpty);
    expect(b.peers, hasLength(1));
    await clock.elapse(const Duration(seconds: 14));
    expect(a.peers, isEmpty);
    expect(b.peers, hasLength(1));
    final handshakes = proxy.sent
        .map((sent) => sent.message)
        .whereType<TransportMessageHandshake>();
    expect(handshakes, hasLength(1));
  });

  test(
    'abandons unanswered handshakes and allocates a fresh session',
    () async {
      proxy.drop = (sent) => sent.message is TransportMessageHandshake;
      await Future.wait([a.start(), b.start()]);
      await flushMessages();
      await clock.elapse(const Duration(seconds: 14));
      expect(a.peers, isEmpty);
      proxy.drop = null;
      await clock.elapse(const Duration(seconds: 6));
      expect(a.peers, hasLength(1));
      final ids = proxy.sent
          .map((sent) => sent.message)
          .whereType<TransportMessageHandshake>()
          .map((message) => message.sessionId)
          .toSet();
      expect(ids.length, greaterThan(1));
    },
  );

  test(
    'buffers immediate data and preserves String order for a late listener',
    () async {
      final payloads = ['{"nested":"café 🌍"}', '', 'line\nline'];
      b.onPeer = (peer) {
        for (final payload in payloads) {
          peer.channel.sink.add(payload);
        }
      };
      await connect();
      final received = <String>[];
      a.peers.single.channel.stream.listen(received.add);
      await flushMessages();
      expect(received, payloads);
    },
  );

  test('routes multiple peers independently in both directions', () async {
    final c = TestTransport(proxy, clock, 'c');
    await connect();
    await c.start();
    await flushMessages();
    expect(a.peers, hasLength(2));
    expect(b.peers, hasLength(2));
    expect(c.peers, hasLength(2));
    final received = <String, List<String>>{};
    for (final peer in a.peers) {
      final messages = received[peer.actor] = [];
      peer.channel.stream.listen(messages.add);
    }
    b.peers.firstWhere((peer) => peer.actor == 'a').channel.sink.add('from b');
    c.peers.firstWhere((peer) => peer.actor == 'a').channel.sink.add('from c');
    final reverse = <String>[];
    c.peers
        .firstWhere((peer) => peer.actor == 'a')
        .channel
        .stream
        .listen(reverse.add);
    a.peers.firstWhere((peer) => peer.actor == 'c').channel.sink.add('to c');
    await flushMessages();
    expect(received, {
      'b': ['from b'],
      'c': ['from c'],
    });
    expect(reverse, ['to c']);
    await c.close();
  });

  for (final activity in ['keepalive', 'data']) {
    test('$activity refreshes the inactivity deadline', () async {
      await connect();
      proxy.drop = (sent) => sent.sender == 'b';
      var closed = false;
      unawaited(a.peers.single.channel.sink.done.then((_) => closed = true));
      await clock.elapse(const Duration(seconds: 14));
      final id =
          (proxy.sent
                      .firstWhere(
                        (sent) => sent.message is TransportMessageHandshake,
                      )
                      .message
                  as TransportMessageHandshake)
              .sessionId;
      proxy.inject(
        'a',
        'b',
        activity == 'data'
            ? TransportMessageData(sessionId: id, data: 'active')
            : TransportMessageKeepalive(id),
      );
      await flushMessages();
      await clock.elapse(const Duration(seconds: 14));
      expect(closed, isFalse);
      await clock.elapse(const Duration(seconds: 1));
      expect(closed, isTrue);
    });
  }

  test(
    'timeout closes both directions and discovery creates a replacement',
    () async {
      await connect();
      final oldA = a.peers.single;
      final oldB = b.peers.single;
      proxy.drop = (sent) => sent.message is TransportMessageKeepalive;
      await clock.elapse(const Duration(seconds: 15));
      await Future.wait([oldA.channel.sink.done, oldB.channel.sink.done]);
      proxy.drop = null;
      await clock.elapse(const Duration(seconds: 5));
      expect(a.peers, hasLength(2));
      expect(b.peers, hasLength(2));
      expect(a.peers.last.channel, isNot(same(oldA.channel)));
    },
  );

  for (final closure in ['sink', 'subscription']) {
    test(
      '$closure closure ends the remote session without waiting for listeners',
      () async {
        await connect();
        final left = a.peers.single.channel;
        final right = b.peers.single.channel;
        if (closure == 'sink') {
          await left.sink.close();
        } else {
          await left.stream.listen((_) {}).cancel();
        }
        await flushMessages();
        await Future.wait([left.sink.done, right.sink.done]);
        expect(await right.stream.toList(), isEmpty);
        await clock.elapse(const Duration(seconds: 5));
        expect(a.peers, hasLength(2));
        expect(b.peers, hasLength(2));
      },
    );
  }

  test('stale session traffic cannot affect a replacement', () async {
    await connect();
    final oldId =
        (proxy.sent
                    .firstWhere(
                      (sent) => sent.message is TransportMessageHandshake,
                    )
                    .message
                as TransportMessageHandshake)
            .sessionId;
    await a.peers.single.channel.sink.close();
    await clock.elapse(const Duration(seconds: 5));
    final received = <String>[];
    b.peers.last.channel.stream.listen(received.add);
    for (final message in <TransportMessage>[
      TransportMessageHandshakeAck(oldId),
      TransportMessageData(sessionId: oldId, data: 'stale'),
      TransportMessageKeepalive(oldId),
      TransportMessageClose(oldId),
    ]) {
      proxy.inject('b', 'a', message);
    }
    a.peers.last.channel.sink.add('current');
    await flushMessages();
    expect(received, ['current']);
    expect(b.peers, hasLength(2));
  });

  test('malformed frames are ignored without refreshing liveness', () async {
    await connect();
    proxy.drop = (sent) => sent.sender == 'b';
    var closed = false;
    unawaited(a.peers.single.channel.sink.done.then((_) => closed = true));
    await clock.elapse(const Duration(seconds: 14));
    for (final bad in [
      42,
      '{bad',
      jsonEncode({
        'actor': 'b',
        'type': 'direct',
        'data': '{"type":"data","sessionId":7}',
      }),
    ]) {
      proxy.injectRaw('a', bad);
    }
    await flushMessages();
    expect(a.errors, isEmpty);
    expect(closed, isFalse);
    await clock.elapse(const Duration(seconds: 1));
    expect(closed, isTrue);
  });

  for (final failure in [false, true]) {
    test(
      'socket ${failure ? 'failure' : 'closure'} ends discovery and peers',
      () async {
        await connect();
        final peer = a.peers.single;
        if (failure) {
          proxy.connections['a']!.sink.addError(
            const FormatException('socket failed'),
          );
        } else {
          unawaited(proxy.connections['a']!.sink.close());
        }
        await a.finished.future;
        await peer.channel.sink.done;
        expect(a.errors, failure ? [isA<FormatException>()] : isEmpty);
        await expectLater(a.start(), throwsStateError);
      },
    );
  }

  test('startup failure is reported by start only', () async {
    await a.close();
    a = TestTransport(
      proxy,
      clock,
      'a',
      open: (_, _) async {
        throw const FormatException('opening failed');
      },
    );
    await expectLater(a.start(), throwsFormatException);
    await a.finished.future;
    expect(a.errors, isEmpty);
  });

  test('close during startup disposes a late connection', () async {
    await a.close();
    final opening = Completer<StreamChannel<Object?>>();
    a = TestTransport(proxy, clock, 'a', open: (_, _) => opening.future);
    final starting = a.start();
    await a.close();
    final connection = await proxy.open(
      'ws://unused',
      const ProxyInit(actor: 'a', group: 'test').toHeaders(),
    );
    opening.complete(connection);
    await starting;
    await flushMessages();
    expect(proxy.connections, isEmpty);
    expect(proxy.sent, isEmpty);
  });

  test('start once and idempotent close', () async {
    await a.start();
    await expectLater(a.start(), throwsStateError);
    await Future.wait([a.close(), a.close()]);
    await a.close();
    await expectLater(a.start(), throwsStateError);
  });

  test('fresh handshake replaces the receiver session', () async {
    await connect();
    final old = b.peers.single.channel;
    proxy.inject('b', 'a', const TransportMessageHandshake('fresh-session'));
    await flushMessages();
    await old.sink.done;
    expect(b.peers, hasLength(2));
    proxy.inject('b', 'a', const TransportMessageHandshake('fresh-session'));
    await flushMessages();
    expect(b.peers, hasLength(2));
  });

  test('stale keepalive cannot extend the active session deadline', () async {
    await connect();
    proxy.drop = (sent) => sent.sender == 'b';
    var closed = false;
    unawaited(a.peers.single.channel.sink.done.then((_) => closed = true));
    await clock.elapse(const Duration(seconds: 14));
    proxy.inject('a', 'b', const TransportMessageKeepalive('old-session'));
    await flushMessages();
    await clock.elapse(const Duration(seconds: 1));
    expect(closed, isTrue);
  });

  test('closing a peer cancels an in-progress outgoing stream', () async {
    await connect();
    final source = StreamController<String>();
    final received = <String>[];
    b.peers.single.channel.stream.listen(received.add);
    final adding = a.peers.single.channel.sink.addStream(source.stream);
    source.add('first');
    await flushMessages();
    expect(received, ['first']);
    await a.peers.single.channel.sink.close();
    await adding;
    expect(source.hasListener, isFalse);
    await source.close();
  });

  test(
    'local sink errors close the session and surface through sink.done',
    () async {
      await connect();
      final sink = a.peers.single.channel.sink;
      final failure = expectLater(sink.done, throwsFormatException);
      sink.addError(const FormatException('local failure'));
      await failure;
      await flushMessages();
      await b.peers.single.channel.sink.done;
      expect(a.errors, isEmpty);
    },
  );

  test('malformed message diagnostics exclude payload contents', () async {
    await a.close();
    final logger = RecordingLogger();
    a = TestTransport(proxy, clock, 'a', logger: logger);
    await connect();
    proxy.injectRaw('a', 'secret-malformed-payload');
    await flushMessages();
    final warnings = logger.entries.where(
      (entry) => entry.level == LogLevel.warning,
    );
    expect(warnings, hasLength(1));
    expect(warnings.single.message, isNot(contains('secret')));
    expect(warnings.single.error, isNull);
  });

  test('close completes even when discovery has no listener', () async {
    final transport = WebSocketProxyTransport(
      baseUrl: 'ws://unused',
      thisActor: 'c',
      group: 'test',
      logger: const NoopLogger(),
      idGenerator: TestIds('c'),
      timeProvider: clock,
      openConnection: proxy.open,
      timerFactory: clock.schedule,
    );
    await transport.start();
    await transport.close();
    expect(await transport.peerTransports.toList(), isEmpty);
  });

  test(
    'real replicators exchange commands and restart above replacement channels',
    () async {
      final stores = [MemoryEventStore(), MemoryEventStore()];
      final replicators = <Replicator>[];
      final running = <Future<void>>[];
      void startReplication(TestTransport transport, MemoryEventStore store) {
        transport.onPeer = (peer) {
          final replicator = Replicator(
            channel: peer.channel.transform(
              StreamChannelTransformer.fromCodec(
                const ReplicationMessageCodec(),
              ),
            ),
            eventStore: store,
            logger: const NoopLogger(),
          );
          replicators.add(replicator);
          running.add(replicator.run());
        };
      }

      startReplication(a, stores[0]);
      startReplication(b, stores[1]);
      final first = command('a', 1);
      expect(await stores[0].addStoredCommand(first), isTrue);
      await connect();
      await flushMessages();
      expect(
        (await stores[1].getStoredCommand(first.commandId))!.toJson(),
        first.toJson(),
      );
      await replicators.first.close();
      await Future.wait(running);
      await clock.elapse(const Duration(seconds: 5));
      expect(replicators, hasLength(4));
      final second = command('b', 1);
      expect(await stores[1].addStoredCommand(second), isTrue);
      await flushMessages();
      expect(
        (await stores[0].getStoredCommand(second.commandId))!.toJson(),
        second.toJson(),
      );
      await Future.wait([a.close(), b.close()]);
      await Future.wait(running);
    },
  );
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
