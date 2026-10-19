import 'package:stream_channel/stream_channel.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';

import 'package:sync/sync.dart';

/// Connects two [CommandReplicator]s through an asynchronous in-memory channel.
class InMemoryCommandReplication {
  final CommandReplicator peer1;
  final CommandReplicator peer2;

  factory InMemoryCommandReplication({
    required EventStoreReplication store1,
    required EventStoreReplication store2,
    required Logger logger,
  }) {
    final channel = StreamChannelController<CommandReplicationMessage>();
    return InMemoryCommandReplication._(
      CommandReplicator(
        channel: channel.local,
        eventStore: store1,
        logger: logger,
      ),
      CommandReplicator(
        channel: channel.foreign,
        eventStore: store2,
        logger: logger,
      ),
    );
  }

  InMemoryCommandReplication._(this.peer1, this.peer2);

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
