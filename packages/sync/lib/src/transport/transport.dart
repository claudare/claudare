import 'package:sync/sync.dart';

abstract interface class Transport {
  /// Returns a ready [ReplicationChannel]
  Future<ReplicationChannel> connect(String peerActor);
}
