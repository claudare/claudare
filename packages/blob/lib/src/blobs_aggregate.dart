import 'package:blob/src/blob_event.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';

/// Tracks active and permanently deleted blob stream IDs.
final class BlobsState implements AggregateState<BlobEvent> {
  final Set<String> activeIds = {};
  final Set<String> deletedIds = {};

  @override
  void apply(EventEnvelope<BlobEvent> envelope) {
    if (envelope.event is BlobCreated) {
      activeIds.add(blobIdFromStream(envelope.streamPath));
    }
  }

  @override
  void onStreamDeleted(StreamDeletion deletion) {
    final id = blobIdFromStream(deletion.streamPath);
    activeIds.remove(id);
    deletedIds.add(id);
  }
}

Aggregate<BlobEvent, BlobsState> blobsAggregate() => Aggregate(
  name: 'blobs-status',
  filter: LogFilter.startsWith(blobStream('')),
  state: BlobsState(),
);
