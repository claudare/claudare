import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/stored_command.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';

class StreamInfo {
  final int version;
  final bool isDeleted;

  const StreamInfo({required this.version, required this.isDeleted});

  const StreamInfo.streamDoesNotExist() : version = -1, isDeleted = false;

  bool streamExists() => version != -1;
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

  /// Broadcasts one change per event saved after listening begins.
  Stream<EventChange> get eventChanges;

  /// A small summary of the current state of the event store.
  Future<EventDatabaseState> getState();

  /// Adds (appends) a command with events. Returns true on successful save.
  /// Returns false when the command's dependencies are not satisfied or the
  /// command is out of order.
  /// This accepts commands received from other actors.
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

  /// Reads events matching [filter] from the inclusive global [fromPosition].
  /// Includes erased records. [EventStore] owns pagination size.
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  );
}

abstract interface class EventStore implements EventStoreReplication {
  /// Returns stream state.
  Future<StreamInfo> getStreamInfo(String streamPath);

  /// Returns the latest log position for a given filter.
  /// Pass in [LogFilter.all] to get the latest position of the event store.
  /// -1 is returned when filter did not match anything.
  Future<int> getLogPosition(LogFilter filter);

  /// Get paginated result from a single stream.
  /// Includes erased records. [EventStore] owns pagination size.
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
  );

  /// Saves results of command execution into the event store.
  /// The caller must validate [CommandChanges.isValid] before saving.
  Future<void> saveChanges(CommandChanges changes);
}
