import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:cqrs/src/cqrs/event/stream_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';

class EventDatabaseState {
  final int lastLocalCommandSequence;
  final int lastLocalEventSequence;
  final VersionVector appliedVersion;

  const EventDatabaseState({
    required this.lastLocalCommandSequence,
    required this.lastLocalEventSequence,
    required this.appliedVersion,
  });
}

abstract interface class EventDatabase {
  int get defaultEventFetchPageSize;

  Future<void> close();
  Future<void> migrate();
  Future<EventDatabaseState> getState();
  Future<int> getStreamVersion(String streamPath);
  Future<PaginatedResult<StreamEvent>> getStreamEvents(
    String streamPath,
    int streamVersionCursor,
    int count,
  );
  Future<PaginatedResult<LocalEvent>> getLocalEvents(
    int localSequenceCursor,
    int count,
  );
  Future<GetStatisticsResult> getStatistics();
  Future<ReplicatedCommand?> getAppliedCommand(CommandId commandId);
  Future<ReplicatedCommand?> getPendingCommand(CommandId commandId);
  Future<ReplicatedEvent?> getAppliedEvent(EventId eventId);
  Future<ReplicatedEvent?> getPendingEvent(EventId eventId);
  Future<List<ReplicatedEvent>> getPendingEvents(CommandId commandId);
  Future<List<AppliedCommand>> getAppliedCommands(
    int localSequenceCursor,
    int count,
  );
  Future<List<AppliedEvent>> getAppliedEvents(CommandId commandId);
  Future<void> appendApplied(AppliedCommand command, List<AppliedEvent> events);
  Future<void> stagePendingCommand(ReplicatedCommand command);
  Future<void> stagePendingEvents(List<ReplicatedEvent> events);
  Future<void> promotePending(
    AppliedCommand command,
    List<AppliedEvent> events,
  );
  Future<void> reset();
}
