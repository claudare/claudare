import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/stored_command.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';

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
  Future<bool> addStoredCommand(StoredCommand command);

  /// Returns a stored command by command ID, or null when absent.
  /// This is used for retrieving commands for syncing.
  Future<StoredCommand?> getStoredCommand(CommandId commandId);
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

  /// Get paginated result from the global log.
  /// [EventStore] owns pagination size.
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition);

  /// Saves results of command execution into the event store.
  Future<void> saveChanges(CommandChanges changes);
}
