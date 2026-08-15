import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_read.dart';
import 'package:cqrs/src/cqrs/event/stored_event_projection_read.dart';
import 'package:cqrs/src/cqrs/event_store/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

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

class ReplicatedCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;

  ReplicatedCommand({
    required this.commandId,
    required this.dependency,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.eventCount,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'replicated commands must produce at least one event',
      );
    }
  }
}

class AppliedCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;
  final int localSequence;

  AppliedCommand({
    required this.commandId,
    required this.dependency,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.eventCount,
    required this.localSequence,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'applied commands must produce at least one event',
      );
    }
  }

  ReplicatedCommand toReplicatedCommand() => ReplicatedCommand(
    commandId: commandId,
    dependency: dependency,
    encoded: encoded,
    startedAt: startedAt,
    completedAt: completedAt,
    eventCount: eventCount,
  );

  factory AppliedCommand.fromReplicatedCommand(
    ReplicatedCommand command, {
    required int localSequence,
  }) => AppliedCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    encoded: command.encoded,
    startedAt: command.startedAt,
    completedAt: command.completedAt,
    eventCount: command.eventCount,
    localSequence: localSequence,
  );
}

class ReplicatedEvent {
  final EventId eventId;
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const ReplicatedEvent({
    required this.eventId,
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
  });

  // TODO: make the order of Applied events required to be sorted
  // perform an assertion rather then sorting
  static List<ReplicatedEvent> fromAppliedEvents(
    Iterable<AppliedEvent> events,
  ) {
    final result =
        events.map((event) => event.toReplicatedEvent()).toList()..sort((a, b) {
          final device = a.eventId.deviceId.compareTo(b.eventId.deviceId);
          if (device != 0) return device;
          final sequence = a.eventId.sequence.compareTo(b.eventId.sequence);
          if (sequence != 0) return sequence;
          return a.eventId.index.compareTo(b.eventId.index);
        });
    return List.unmodifiable(result);
  }
}

class AppliedEvent {
  final EventId eventId;
  final String streamId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int localSequence;
  final int streamVersion;

  const AppliedEvent({
    required this.eventId,
    required this.streamId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
    required this.streamVersion,
  });

  ReplicatedEvent toReplicatedEvent() => ReplicatedEvent(
    eventId: eventId,
    streamId: streamId,
    encodedEvent: encodedEvent,
    occuredAt: occuredAt,
  );

  factory AppliedEvent.fromReplicatedEvent(
    ReplicatedEvent event, {
    required int localSequence,
    required int streamVersion,
  }) => AppliedEvent(
    eventId: event.eventId,
    streamId: event.streamId,
    encodedEvent: event.encodedEvent,
    occuredAt: event.occuredAt,
    localSequence: localSequence,
    streamVersion: streamVersion,
  );
}

// TODO: this needs cleanup and more consideration.
bool replicatedCommandsEqual(ReplicatedCommand a, ReplicatedCommand b) =>
    a.commandId == b.commandId &&
    a.dependency == b.dependency &&
    a.encoded.kind == b.encoded.kind &&
    _bytesEqual(a.encoded.bytes, b.encoded.bytes) &&
    a.startedAt == b.startedAt &&
    a.completedAt == b.completedAt &&
    a.eventCount == b.eventCount;

bool replicatedEventsEqual(ReplicatedEvent a, ReplicatedEvent b) =>
    a.eventId == b.eventId &&
    a.streamId == b.streamId &&
    a.encodedEvent.kind == b.encodedEvent.kind &&
    _bytesEqual(a.encodedEvent.bytes, b.encodedEvent.bytes) &&
    a.occuredAt == b.occuredAt;

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

abstract interface class EventDatabase {
  int get defaultEventFetchPageSize;

  Future<void> migrate();
  Future<EventDatabaseState> getState();
  Future<int> getStreamVersion(String streamId);
  Future<PaginatedResult<StoredEventCommandRead>> getStreamEvents(
    String streamId,
    int streamVersionCursor,
    int count,
  );
  Future<PaginatedResult<StoredEventProjectionRead>> getLocalEvents(
    PatternFilter patternFilter,
    int localSequenceCursor,
    int count,
  );
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
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
