import 'package:stream_channel/stream_channel.dart';

/// Peer transport is a link of communication with another peer.
/// They are discovered automatically by the [Transport].
/// Web socket proxy uses broadcast to establish connections.
/// Closing the channel sink or cancelling its stream ends the peer session.
class PeerTransport {
  final String actor;
  final StreamChannel<String> channel;

  const PeerTransport({required this.actor, required this.channel});
}

/// Discovers ordered, single-peer channels independently of replication.
abstract interface class Transport {
  /// Single-subscription discovery stream. Listen before calling [start].
  Stream<PeerTransport> get peerTransports;

  /// Starts discovery once. A closed transport cannot restart.
  Future<void> start();

  /// Ends discovery and every peer channel. Repeated calls are safe.
  Future<void> close();
}
