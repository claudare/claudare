import 'package:stream_channel/stream_channel.dart';

import '../transport/transport.dart';

/// Creates in-memory peer connections for tests.
abstract final class SyncTestHelper {
  /// Creates opposite ends of an in-memory connection between two actors.
  static ({PeerTransport first, PeerTransport second}) createPeerPair({
    required String firstActor,
    required String secondActor,
  }) {
    final channel = StreamChannelController<String>();
    return (
      first: PeerTransport(actor: secondActor, channel: channel.local),
      second: PeerTransport(actor: firstActor, channel: channel.foreign),
    );
  }
}
