import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/stored_command.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';

/// Local availability of a blob referenced by a committed command.
enum BlobStatus {
  /// The blob is required but has not been marked available locally.
  pending,

  /// The complete blob bytes have been saved locally.
  available,
}

class EventDatabaseState {
  final int? lastCommandLogPosition;
  final int? lastEventLogPosition;
  final CommandDependency logVersion;

  const EventDatabaseState({
    required this.lastCommandLogPosition,
    required this.lastEventLogPosition,
    required this.logVersion,
  });
}

enum ChangeOrigin {
  /// triggered on saveChanges
  local,

  /// triggered on addStoredCommand
  remote,
}

/// Notification about a command being added to the event store.
final class CommandChange {
  final ChangeOrigin origin;
  final CommandId commandId;

  const CommandChange({required this.origin, required this.commandId});
}

/// Notification about an event being added to the event store.
final class EventChange {
  /// Stream path of the saved event.
  final String stream;

  const EventChange({required this.stream});
}

abstract interface class EventStoreReplication {
  /// Broadcasts commands saved after listening begins.
  Stream<CommandChange> get commandChanges;

  /// A small summary of the current state of the event store.
  Future<EventDatabaseState> getState();

  /// Adds (appends) a command with events. Returns true on successful save.
  /// Returns false when the command's dependencies are not satisfied or the
  /// command is out of order.
  /// This accepts commands received from other actors.
  /// New blob references start pending. Reusing a blob ID in another command
  /// throws [StateError].
  Future<bool> addStoredCommand(StoredCommand command);

  /// Returns a stored command by command ID, or null when absent.
  /// This is used for retrieving commands for syncing.
  Future<StoredCommand?> getStoredCommand(CommandId commandId);

  /// Returns at most [count] command IDs not covered by [dependency].
  /// Local command log order ensures each ID can advance [dependency] without
  /// holes and each command's dependencies precede it or are already covered.
  Future<List<CommandId>> getNextCommandIds(
    CommandDependency dependency,
    int count,
  );

  /// Returns local availability, or null for an unreferenced blob ID.
  Future<BlobStatus?> getBlobStatus(String blobId);

  /// Reads pending IDs in local log order from the inclusive [cursor].
  /// Start with cursor zero. Negative cursors throw [ArgumentError].
  /// [PaginatedResult.next] is the last returned position plus one, or null
  /// when the page is empty.
  /// Cursors remain stable when earlier blobs become available. Restart from
  /// zero to retry pending IDs skipped during an earlier scan.
  /// [EventStore] owns pagination size.
  Future<PaginatedResult<String>> getPendingBlobIds(int cursor);

  /// Marks a referenced blob available after its bytes are durably saved.
  /// Repeated calls succeed. Throws [StateError] for an unreferenced ID.
  Future<void> markBlobAvailable(String blobId);
}

abstract interface class EventStore implements EventStoreReplication {
  /// Broadcasts one change per event saved after listening begins.
  Stream<EventChange> get eventChanges;

  /// Quick latest lookup of the last stream's version.
  Future<int?> getStreamVersion(String streamPath);

  /// Get paginated result from a single stream.
  /// [EventStore] owns pagination size.
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
  );

  /// Reads events matching [filter] from the inclusive global [fromPosition].
  /// [EventStore] owns pagination size.
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  );

  /// Saves results of command execution into the event store.
  /// The caller must validate [CommandChanges.isValid] before saving.
  /// Blob bytes must already be saved; their references start available.
  /// Reusing a blob ID in another command or at another index throws
  /// [StateError].
  Future<void> saveChanges(CommandChanges changes);
}
