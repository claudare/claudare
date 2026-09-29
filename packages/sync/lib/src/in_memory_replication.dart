import 'package:stream_channel/stream_channel.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';

import 'package:sync/sync.dart';

/// Connects two [Replicator]s through an asynchronous in-memory channel.
class InMemoryReplication {
  final Replicator peer1;
  final Replicator peer2;

  factory InMemoryReplication({
    required EventStoreReplication store1,
    required EventStoreReplication store2,
    required Logger logger,
  }) {
    final channel = StreamChannelController<ReplicationMessage>();
    return InMemoryReplication._(
      Replicator(channel: channel.local, eventStore: store1, logger: logger),
      Replicator(channel: channel.foreign, eventStore: store2, logger: logger),
    );
  }

  InMemoryReplication._(this.peer1, this.peer2);

  /// Runs both peers until disconnection, surfacing either peer's failure.
  Future<void> run({
    bool peer1Receives = true,
    bool peer2Receives = true,
  }) async {
    await Future.wait([
      peer1.run(receive: peer1Receives),
      peer2.run(receive: peer2Receives),
    ]);
  }

  /// Closes the running connection and waits for both peers to stop.
  Future<void> close() async {
    await Future.wait([peer1.close(), peer2.close()]);
  }
}
