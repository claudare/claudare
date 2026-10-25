import 'dart:async';

import 'package:test/test.dart';
import 'package:transport/transport.dart';
import 'package:transport_test/transport_test.dart';

void main() {
  test('transports discover each other and exchange messages', () async {
    final network = MemoryTransportNetwork();
    final first = network.createTransport(actor: 'first');
    final second = network.createTransport(actor: 'second');
    addTearDown(() async => Future.wait([first.close(), second.close()]));
    final firstPeers = <PeerTransport>[];
    final secondPeers = <PeerTransport>[];
    first.peerTransports.listen(firstPeers.add);
    second.peerTransports.listen(secondPeers.add);

    await Future.wait([first.start(), second.start()]);
    await _flush();

    expect(firstPeers.map((peer) => peer.actor), ['second']);
    expect(secondPeers.map((peer) => peer.actor), ['first']);
    final received = <String>[];
    secondPeers.single.channel.stream.listen(received.add);
    firstPeers.single.channel.sink.add('one');
    firstPeers.single.channel.sink.add('two');
    await _flush();
    expect(received, ['one', 'two']);
  });

  test('a new transport discovers every active peer once', () async {
    final network = MemoryTransportNetwork();
    final transports = [
      network.createTransport(actor: 'a'),
      network.createTransport(actor: 'b'),
      network.createTransport(actor: 'c'),
    ];
    addTearDown(() async {
      await Future.wait(transports.map((transport) => transport.close()));
    });
    final discovered = <String, List<String>>{
      for (final transport in transports) transport.actor: [],
    };
    for (final transport in transports) {
      transport.peerTransports.listen(
        (peer) => discovered[transport.actor]!.add(peer.actor),
      );
      await transport.start();
    }
    await _flush();

    expect(discovered['a'], ['b', 'c']);
    expect(discovered['b'], ['a', 'c']);
    expect(discovered['c'], ['a', 'b']);
  });

  test('separate networks do not discover each other', () async {
    final first = MemoryTransportNetwork().createTransport(actor: 'first');
    final second = MemoryTransportNetwork().createTransport(actor: 'second');
    addTearDown(() async => Future.wait([first.close(), second.close()]));
    final firstPeers = <PeerTransport>[];
    final secondPeers = <PeerTransport>[];
    first.peerTransports.listen(firstPeers.add);
    second.peerTransports.listen(secondPeers.add);

    await Future.wait([first.start(), second.start()]);
    await _flush();

    expect(firstPeers, isEmpty);
    expect(secondPeers, isEmpty);
  });

  test('closing a transport closes both peer endpoints', () async {
    final network = MemoryTransportNetwork();
    final first = network.createTransport(actor: 'first');
    final second = network.createTransport(actor: 'second');
    addTearDown(() async => Future.wait([first.close(), second.close()]));
    final firstPeer = first.peerTransports.first;
    final secondPeer = second.peerTransports.first;
    await Future.wait([first.start(), second.start()]);
    final firstEndpoint = await firstPeer;
    final secondEndpoint = await secondPeer;
    final firstDone = firstEndpoint.channel.stream.drain<void>();
    final secondDone = secondEndpoint.channel.stream.drain<void>();

    await first.close();

    await Future.wait([firstDone, secondDone]);
  });

  test('actor can be reused after its transport closes', () async {
    final network = MemoryTransportNetwork();
    final first = network.createTransport(actor: 'actor');
    final duplicate = network.createTransport(actor: 'actor');
    await first.start();
    await expectLater(duplicate.start(), throwsStateError);
    await first.close();
    final replacement = network.createTransport(actor: 'actor');

    await replacement.start();

    await Future.wait([duplicate.close(), replacement.close()]);
  });

  for (final actor in ['', ' \t\n ']) {
    test('blank actor is rejected', () {
      expect(
        () => MemoryTransportNetwork().createTransport(actor: actor),
        throwsArgumentError,
      );
    });
  }

  test('start is single-use and close is idempotent', () async {
    final transport = MemoryTransportNetwork().createTransport(actor: 'actor');
    await transport.start();

    await expectLater(transport.start(), throwsStateError);
    await Future.wait([transport.close(), transport.close()]);
    await transport.close();
    await expectLater(transport.start(), throwsStateError);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
