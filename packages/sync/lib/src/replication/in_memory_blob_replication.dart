import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';

import '../sync_defaults.dart';
import 'blob_replication_message.dart';
import 'blob_replicator.dart';

/// Connects two [BlobReplicator]s through an asynchronous in-memory channel.
class InMemoryBlobReplication {
  final BlobReplicator peer1;
  final BlobReplicator peer2;

  factory InMemoryBlobReplication({
    required EventStoreReplication store1,
    required EventStoreReplication store2,
    required BlobStore? blobStore1,
    required BlobStore? blobStore2,
    required Logger logger,
    Duration retryInterval = SyncDefaults.blobRetryInterval,
    Timer Function(Duration delay, void Function() callback) timerFactory =
        Timer.new,
  }) {
    final channel = StreamChannelController<BlobReplicationMessage>();
    return InMemoryBlobReplication._(
      BlobReplicator(
        channel: channel.local,
        eventStore: store1,
        blobStore: blobStore1,
        logger: logger,
        retryInterval: retryInterval,
        timerFactory: timerFactory,
      ),
      BlobReplicator(
        channel: channel.foreign,
        eventStore: store2,
        blobStore: blobStore2,
        logger: logger,
        retryInterval: retryInterval,
        timerFactory: timerFactory,
      ),
    );
  }

  InMemoryBlobReplication._(this.peer1, this.peer2);

  /// Runs both peers until disconnection, surfacing either peer's failure.
  /// Restart requires a new helper, which scans pending blobs from zero.
  Future<void> run() => Future.wait([peer1.run(), peer2.run()]);

  /// Closes both running peers without closing their stores.
  Future<void> close() => Future.wait([peer1.close(), peer2.close()]);
}
