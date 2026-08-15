import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event_store/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_administration.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_projection.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:cqrs/src/cqrs/exception/replicated_command_conflict.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:mutex/mutex.dart';

enum StageReplicatedCommandResult { staged, alreadyPresent }

class EventStore
    implements
        EventStoreCommand,
        EventStoreProjection,
        EventStoreAdministration {
  final EventDatabase _database;
  final int _eventFetchPageSize;
  final ReadWriteMutex _mutex = ReadWriteMutex();

  EventStore(EventDatabase database, {int? eventFetchPageSize})
    : _database = database,
      _eventFetchPageSize =
          eventFetchPageSize ?? database.defaultEventFetchPageSize;

  Future<void> migrate() => _mutex.protectWrite(() async {
    try {
      await _database.migrate();
    } on Exception catch (cause) {
      throw EventStoreException(
        'Failed to migrate event database',
        cause: cause,
      );
    }
  });

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String streamId,
    int streamVersionCursor,
  ) => _mutex.protectRead(() async {
    try {
      final version = await _database.getStreamVersion(streamId);
      final events = await _database.getStreamEvents(
        streamId,
        streamVersionCursor,
        _eventFetchPageSize,
      );
      return GetStreamEventsResult(
        originatingStreamVersion: version,
        events: events,
      );
    } on Exception catch (cause) {
      throw EventStoreException(
        "Failed to get stream events for '$streamId'",
        cause: cause,
      );
    }
  });

  @override
  Future<GetStreamInfoResult?> getStreamInfo(String streamId) =>
      _mutex.protectRead(() async {
        try {
          final version = await _database.getStreamVersion(streamId);
          return version == 0
              ? null
              : GetStreamInfoResult(originatingStreamVersion: version);
        } on Exception catch (cause) {
          throw EventStoreException(
            "Failed to get stream info for '$streamId'",
            cause: cause,
          );
        }
      });

  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    final deviceId = 0; // own device id is always 0
    if (appends.events.isEmpty) return SaveChangesResult.empty();
    if (!appends.isValid()) {
      throw ArgumentError('every appended event must have one stream lock');
    }

    return _mutex.protectWrite(() async {
      try {
        final state = await _database.getState();
        final streamVersions = <String, int>{};
        for (final lock in appends.localLocks) {
          final current = await _database.getStreamVersion(lock.streamId);
          if (current != lock.originatingStreamVersion) {
            throw ConcurrencyProblem();
          }
          streamVersions[lock.streamId] = current;
        }

        final commandId = CommandId(
          deviceId,
          state.appliedVersion.value(deviceId) + 1,
        );
        final replicatedEvents = [
          for (var i = 0; i < appends.events.length; i++)
            ReplicatedEvent(
              eventId: EventId(deviceId, commandId.sequence, i),
              streamId: appends.events[i].streamId,
              encodedEvent: appends.events[i].encodedEvent,
              occuredAt: appends.events[i].occuredAt,
            ),
        ];
        final replicated = ReplicatedCommand(
          commandId: commandId,
          dependency: state.appliedVersion,
          encoded: command.encoded,
          startedAt: command.startedAt,
          completedAt: command.completedAt,
          eventCount: replicatedEvents.length,
        );

        var localEventSequence = state.lastLocalEventSequence;
        final appliedEvents = <AppliedEvent>[];
        for (var i = 0; i < replicatedEvents.length; i++) {
          final event = replicatedEvents[i];
          final streamVersion = (streamVersions[event.streamId] ?? 0) + 1;
          streamVersions[event.streamId] = streamVersion;
          appliedEvents.add(
            AppliedEvent(
              eventId: event.eventId,
              streamId: event.streamId,
              encodedEvent: event.encodedEvent,
              occuredAt: event.occuredAt,
              localSequence: ++localEventSequence,
              streamVersion: streamVersion,
            ),
          );
        }

        await _database.appendApplied(
          AppliedCommand.fromReplicatedCommand(
            replicated,
            localSequence: state.lastLocalCommandSequence + 1,
          ),
          appliedEvents,
        );
        return SaveChangesResult(
          orders: [
            for (final event in appliedEvents)
              StreamAppendOrder(localSequence: event.localSequence),
          ],
        );
      } on ConcurrencyProblem {
        rethrow;
      } on Exception catch (cause) {
        throw EventStoreException(
          'Failed to append command batch',
          cause: cause,
        );
      }
    });
  }

  Future<StageReplicatedCommandResult> stageReplicatedCommand(
    ReplicatedCommand command,
  ) => _mutex.protectWrite(() async {
    try {
      final commandId = command.commandId;
      final existing =
          await _database.getAppliedCommand(commandId) ??
          await _database.getPendingCommand(commandId);
      if (existing != null) {
        if (replicatedCommandsEqual(existing, command)) {
          return StageReplicatedCommandResult.alreadyPresent;
        }
        throw ReplicatedCommandConflict(commandId);
      }
      await _database.stagePendingCommand(command);
      return StageReplicatedCommandResult.staged;
    } on ReplicatedCommandConflict {
      rethrow;
    } on Exception catch (cause) {
      throw EventStoreException(
        'Failed to stage replicated command',
        cause: cause,
      );
    }
  });

  Future<StageReplicatedCommandResult> stageReplicatedEvents(
    List<ReplicatedEvent> events,
  ) => _mutex.protectWrite(() async {
    try {
      final unique = <EventId, ReplicatedEvent>{};
      for (final event in events) {
        final duplicate = unique[event.eventId];
        if (duplicate != null && !replicatedEventsEqual(duplicate, event)) {
          throw ReplicatedCommandConflict(event.eventId);
        }
        unique[event.eventId] = event;
      }
      final staged = <ReplicatedEvent>[];
      for (final event in unique.values) {
        final existing =
            await _database.getAppliedEvent(event.eventId) ??
            await _database.getPendingEvent(event.eventId);
        if (existing == null) {
          staged.add(event);
        } else if (!replicatedEventsEqual(existing, event)) {
          throw ReplicatedCommandConflict(event.eventId);
        }
      }
      if (staged.isEmpty) return StageReplicatedCommandResult.alreadyPresent;
      await _database.stagePendingEvents(staged);
      return StageReplicatedCommandResult.staged;
    } on ReplicatedCommandConflict {
      rethrow;
    } on Exception catch (cause) {
      throw EventStoreException(
        'Failed to stage replicated events',
        cause: cause,
      );
    }
  });

  Future<bool> promotePendingCommand(CommandId commandId) =>
      _mutex.protectWrite(() async {
        try {
          final command = await _database.getPendingCommand(commandId);
          if (command == null) return false;
          final state = await _database.getState();
          if (!state.appliedVersion.contains(command.dependency)) {
            return false;
          }
          if (state.appliedVersion.value(commandId.deviceId) + 1 !=
              commandId.sequence) {
            return false;
          }

          final pendingEvents = await _database.getPendingEvents(commandId);
          if (pendingEvents.length != command.eventCount) return false;
          for (var i = 0; i < pendingEvents.length; i++) {
            if (pendingEvents[i].eventId.index != i) return false;
          }

          final streamVersions = <String, int>{};
          var localEventSequence = state.lastLocalEventSequence;
          final events = <AppliedEvent>[];
          for (final event in pendingEvents) {
            final current =
                streamVersions[event.streamId] ??
                await _database.getStreamVersion(event.streamId);
            final next = current + 1;
            streamVersions[event.streamId] = next;
            events.add(
              AppliedEvent(
                eventId: event.eventId,
                streamId: event.streamId,
                encodedEvent: event.encodedEvent,
                occuredAt: event.occuredAt,
                localSequence: ++localEventSequence,
                streamVersion: next,
              ),
            );
          }
          await _database.promotePending(
            AppliedCommand.fromReplicatedCommand(
              command,
              localSequence: state.lastLocalCommandSequence + 1,
            ),
            events,
          );
          return true;
        } on Exception catch (cause) {
          throw EventStoreException(
            'Failed to promote pending command $commandId',
            cause: cause,
          );
        }
      });

  Future<List<AppliedCommand>> getAppliedCommands(int localSequenceCursor) =>
      _mutex.protectRead(() async {
        try {
          return await _database.getAppliedCommands(
            localSequenceCursor,
            _eventFetchPageSize,
          );
        } on Exception catch (cause) {
          throw EventStoreException(
            'Failed to get applied commands',
            cause: cause,
          );
        }
      });

  Future<List<AppliedEvent>> getAppliedEvents(CommandId commandId) =>
      _mutex.protectRead(() async {
        try {
          return await _database.getAppliedEvents(commandId);
        } on Exception catch (cause) {
          throw EventStoreException(
            'Failed to get applied events for $commandId',
            cause: cause,
          );
        }
      });

  @override
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int sequenceNumber,
  ) => _mutex.protectRead(() async {
    try {
      return await _database.getLocalEvents(
        patternFilter,
        sequenceNumber,
        _eventFetchPageSize,
      );
    } on Exception catch (cause) {
      throw EventStoreException('Failed to get local events', cause: cause);
    }
  });

  @override
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) => _mutex.protectRead(() async {
    try {
      return await _database.getLocalLastEvent(patternFilter);
    } on Exception catch (cause) {
      throw EventStoreException('Failed to get last local event', cause: cause);
    }
  });

  @override
  Future<GetStatisticsResult> getStatistics() => _mutex.protectRead(() async {
    try {
      return await _database.getStatistics();
    } on Exception catch (cause) {
      throw EventStoreException('Failed to get statistics', cause: cause);
    }
  });

  @override
  Future<void> reset() => _mutex.protectWrite(() async {
    try {
      await _database.reset();
    } on Exception catch (cause) {
      throw EventStoreException('Failed to reset event database', cause: cause);
    }
  });
}
