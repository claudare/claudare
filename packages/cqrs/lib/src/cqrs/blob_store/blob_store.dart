import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/blob/blob_id.dart';
import 'package:cqrs/src/cqrs/blob/local_blob_save.dart';
import 'package:cqrs/src/cqrs/blob/stored_blob.dart';

enum ChangeOrigin {
  /// triggered on storeLocal
  local,

  /// triggered on applyRemote
  remote,
}

/// Notification about a blob being added to the blob store.
final class BlobChange {
  final ChangeOrigin origin;
  final BlobId commandId;

  const BlobChange({required this.origin, required this.commandId});
}

/// An interface for syncing blobs across actors.
/// Currently, the streaming replication (sending ranges) is not supported. The
/// whole blob needs to be loaded in the memory to be sent/received from another
/// peer.
abstract interface class BlobStoreReplication {
  /// Broadcasts blob changes as they happen.
  Stream<BlobChange> get blobChanges;

  /// A vector for replication purposes.
  /// This should work similar to the event replication.
  Future<CommandDependency> getLatestVector();

  /// Adds (appends, saves) a blob. Returns true on successful save.
  /// Returns false when the blob is saved out of order.
  Future<bool> applyRemote(StoredBlob blob);

  /// Returns a stored blob by ts ID, or null when absent.
  /// This is used for retrieving blobs for syncing.
  Future<StoredBlob?> get(BlobId blobId);

  /// Returns at most [count] blob IDs right in front of the [vector].
  /// They will be replicated in that order.
  Future<List<CommandId>> getNextIds(CommandDependency vector, int count);
}

abstract interface class BlobStore implements BlobStoreReplication {
  /// Saves emitted blobs from the results of command execution.
  Future<void> storeLocal(LocalBlobSave localSave);
}
