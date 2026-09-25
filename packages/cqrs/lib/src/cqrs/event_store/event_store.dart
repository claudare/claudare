import 'package:cqrs/src/cqrs/command/command_dependency.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/stored_command.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';

class GetStatisticsResult {
  final int eventCount;
  final int storageSize; // bytes

  GetStatisticsResult({required this.eventCount, required this.storageSize});
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

abstract interface class EventStore {
  /// Various statistics about the event store.
  Future<GetStatisticsResult> getStatistics();

  /// A small summary of the current state of the event store.
  Future<EventDatabaseState> getState();

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

  /// Adds (appends) a command with events. Returns true on successful save.
  /// Returns false when the command's dependencies are not satisfied or the
  /// command is out of order.
  /// This accepts commands received from other actors.
  Future<bool> addStoredCommand(StoredCommand command);

  /// Returns a stored command by command ID, or null when absent.
  /// This is used for retrieving commands for syncing.
  Future<StoredCommand?> getStoredCommand(CommandId commandId);
}
