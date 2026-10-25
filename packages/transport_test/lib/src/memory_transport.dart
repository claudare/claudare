import 'dart:async';

import 'package:transport/transport.dart';

import 'memory_peer_pair.dart';

/// An isolated discovery domain for in-memory transports.
class MemoryTransportNetwork {
  final _active = <String, MemoryTransport>{};

  /// Creates a transport that will discover other transports on this network.
  MemoryTransport createTransport({required String actor}) {
    if (actor.trim().isEmpty) {
      throw ArgumentError.value(actor, 'actor', 'Must be nonempty');
    }
    return MemoryTransport._(this, actor);
  }

  void _start(MemoryTransport transport) {
    if (_active.containsKey(transport.actor)) {
      throw StateError('Actor is already active');
    }
    final peers = _active.values.toList();
    _active[transport.actor] = transport;
    for (final peer in peers) {
      _MemoryConnection(transport, peer);
    }
  }

  void _remove(MemoryTransport transport) {
    if (identical(_active[transport.actor], transport)) {
      _active.remove(transport.actor);
    }
  }
}

/// A deterministic in-memory [Transport] for tests.
class MemoryTransport implements Transport {
  final MemoryTransportNetwork _network;

  /// Actor announced to other transports on the same network.
  final String actor;

  final _peers = StreamController<PeerTransport>();
  final _connections = <String, _MemoryConnection>{};
  bool _started = false;
  bool _closed = false;
  Future<void>? _closing;

  MemoryTransport._(this._network, this.actor);

  @override
  Stream<PeerTransport> get peerTransports => _peers.stream;

  @override
  Future<void> start() async {
    if (_started || _closed) {
      throw StateError('Transport cannot be started again');
    }
    _started = true;
    _network._start(this);
  }

  void _attach(MemoryTransport peer, _MemoryConnection connection) {
    _connections[peer.actor] = connection;
    _peers.add(connection.peerFor(this));
  }

  void _detach(MemoryTransport peer, _MemoryConnection connection) {
    if (identical(_connections[peer.actor], connection)) {
      _connections.remove(peer.actor);
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _network._remove(this);
    final connections = _connections.values.toSet();
    _connections.clear();
    unawaited(_peers.close());
    return _closing = Future.wait(
      connections.map((connection) => connection.close()),
    ).then<void>((_) {});
  }
}

class _MemoryConnection {
  final MemoryTransport first;
  final MemoryTransport second;
  late final PeerTransport _firstPeer;
  late final PeerTransport _secondPeer;
  Future<void>? _closing;

  _MemoryConnection(this.first, this.second) {
    final pair = createMemoryPeerPair(
      firstActor: first.actor,
      secondActor: second.actor,
    );
    _firstPeer = pair.first;
    _secondPeer = pair.second;
    first._attach(second, this);
    second._attach(first, this);
    unawaited(_firstPeer.channel.sink.done.then(_closed, onError: _failed));
    unawaited(_secondPeer.channel.sink.done.then(_closed, onError: _failed));
  }

  PeerTransport peerFor(MemoryTransport transport) =>
      identical(transport, first) ? _firstPeer : _secondPeer;

  void _closed(Object? _) => unawaited(close());

  void _failed(Object _, StackTrace _) => unawaited(close());

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closing = Future<void>.value();
    first._detach(second, this);
    second._detach(first, this);
    unawaited(_closeSink(_firstPeer));
    unawaited(_closeSink(_secondPeer));
    return _closing!;
  }

  Future<void> _closeSink(PeerTransport peer) async {
    try {
      await peer.channel.sink.close();
    } on Exception {
      // The other endpoint still receives closure from the first sink.
    }
  }
}
