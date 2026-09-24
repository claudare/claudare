import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/log_command.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';

class EventDatabaseState {
  final int? lastCommandLogPosition;
  final int? lastEventLogPosition;
  final VersionVector logVersion;

  const EventDatabaseState({
    required this.lastCommandLogPosition,
    required this.lastEventLogPosition,
    required this.logVersion,
  });
}

abstract interface class EventDatabase {
  int get defaultEventFetchPageSize;

  // general state
  Future<GetStatisticsResult> getStatistics();
  Future<EventDatabaseState> getState();

  // reading
  Future<int?> getStreamVersion(String streamPath);
  Future<PaginatedResult<LogEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
    int count,
  );
  Future<PaginatedResult<LogEvent>> getLogEvents(int fromPosition, int count);

  // writing
  Future<void> appendLog(StagedCommand command, List<StagedEvent> events);

  // replication... this needs a nice cleanup...
  Future<StagedCommand?> getLogCommand(CommandId commandId);
  Future<StagedCommand?> getStagedCommand(CommandId commandId);
  Future<StagedEvent?> getLogEvent(EventId eventId);
  Future<StagedEvent?> getStagedEvent(EventId eventId);
  Future<List<LogCommand>> getLogCommands(int fromPosition, int count);
  Future<List<LogEvent>> getLogEventsForCommand(CommandId commandId);
  Future<void> stageCommand(StagedCommand command);
  Future<void> stageEvents(List<StagedEvent> events);
  Future<bool> promoteStaged(CommandId commandId);
}
