import 'package:stream_channel/stream_channel.dart';
import 'package:transport/transport.dart';

/// Creates opposite ends of an in-memory connection between two actors.
({PeerTransport first, PeerTransport second}) createMemoryPeerPair({
  required String firstActor,
  required String secondActor,
}) {
  final channel = StreamChannelController<String>();
  return (
    first: PeerTransport(actor: secondActor, channel: channel.local),
    second: PeerTransport(actor: firstActor, channel: channel.foreign),
  );
}
