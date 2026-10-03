import 'package:stream_channel/stream_channel.dart';

/// Peer transport is a link of communication with another peer.
/// They are discovered automatically by the [Transport].
/// Web socket proxy uses broadcast to establish connections.
class PeerTransport {
  final String actor;
  final StreamChannel<String> channel;

  const PeerTransport({required this.actor, required this.channel});
}

abstract interface class Transport {
  Stream<PeerTransport> get peerTransports;

  Future<void> start();
  Future<void> close();
}
