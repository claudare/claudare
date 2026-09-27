import 'package:stream_channel/stream_channel.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/replication/message.dart';

typedef ReplicationChannel = StreamChannel<ReplicationMessage>;

class Replicator {
  final ReplicationChannel _channel;
  final EventStoreReplication _eventStore;

  const Replicator({required this._channel, required this._eventStore});
}

class InMemoryReplication {
  final Replicator peer1;
  final Replicator peer2;

  const InMemoryReplication({required this.peer1, required this.peer2});
}
