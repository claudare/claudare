import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:cqrs/src/cqrs/exception/replicated_command_conflict.dart';
import 'package:mutex/mutex.dart';

enum StageReplicatedCommandResult { staged, alreadyPresent }

class GetStreamInfoResult {
  final int? originatingStreamVersion;

  const GetStreamInfoResult({required this.originatingStreamVersion});
}

class GetStatisticsResult {
  final int eventCount;
  final int storageSize; // bytes

  GetStatisticsResult({required this.eventCount, required this.storageSize});
}

/// Event store is responsible for storing commands and events for a
/// `CqrsRuntime`. Do not reuse [EventDatabase] or [EventStore] across
/// different `CqrsRuntime` instances.
class EventStore {
  final EventDatabase _database;
  final int _eventFetchPageSize;
  final ReadWriteMutex _mutex = ReadWriteMutex();
  final StreamController<void> _appliedChangesController =
      StreamController<void>.broadcast(sync: false);

  EventStore(EventDatabase database, {int? eventFetchPageSize})
    : _database = database,
      _eventFetchPageSize =
          eventFetchPageSize ?? database.defaultEventFetchPageSize;

  Stream<void> get appliedChanges => _appliedChangesController.stream;

  Future<GetStreamInfoResult?> getStreamInfo(String streamPath) =>
      _mutex.protectRead(() async {
        try {
          final version = await _database.getStreamVersion(streamPath);
          return version == null
              ? null
              : GetStreamInfoResult(originatingStreamVersion: version);
        } on Exception catch (cause) {
          throw EventStoreException(
            "Failed to get stream info for '$streamPath'",
            cause: cause,
          );
        }
      });

  Future<void> saveChanges(CommandChanges changes) async {
    final deviceId = 0; // own device id is always 0
    if (changes.events.isEmpty) return;
    if (!changes.isValid()) {
      throw ArgumentError('every appended event must have one stream lock');
    }

    await _mutex.protectWrite(() async {
      try {
        final state = await _database.getState();
        if (!state.appliedVersion.contains(changes.dependency)) {
          throw StateError('command dependency is not applied');
        }
        for (final lock in changes.locks) {
          final current = await _database.getStreamVersion(lock.streamPath);
          if (current != lock.originatingStreamVersion) {
            throw ConcurrencyProblem();
          }
        }

        final commandId = CommandId(
          deviceId,
          state.appliedVersion.value(deviceId) + 1,
        );
        final events = <ReplicatedEvent>[];
        for (var i = 0; i < changes.events.length; i++) {
          final event = changes.events[i];
          events.add(
            ReplicatedEvent(
              eventId: EventId(deviceId, commandId.sequence, i),
              streamPath: event.streamPath,
              encodedEvent: event.encodedEvent,
              occuredAt: event.occuredAt,
            ),
          );
        }

        await _database.appendApplied(
          ReplicatedCommand(
            commandId: commandId,
            dependency: changes.dependency,
            encoded: changes.encoded,
            startedAt: changes.startedAt,
            completedAt: changes.completedAt,
            eventCount: events.length,
          ),
          events,
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
    _appliedChangesController.add(null);
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
        if (duplicate != null && duplicate != event) {
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
        } else if (existing != event) {
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

  Future<bool> promotePendingCommand(CommandId commandId) async {
    final promoted = await _mutex.protectWrite(() async {
      try {
        return await _database.promotePending(commandId);
      } on Exception catch (cause) {
        throw EventStoreException(
          'Failed to promote pending command $commandId',
          cause: cause,
        );
      }
    });
    if (promoted) _appliedChangesController.add(null);
    return promoted;
  }

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

  PaginatedReader<StoredEvent> getStreamReader(
    String streamPath, {
    int fromVersion = 0,
  }) => PaginatedReader(
    (cursor) => _readStreamPage(streamPath, cursor),
    initialCursor: fromVersion,
  );

  Future<PaginatedResult<StoredEvent>> _readStreamPage(
    String streamPath,
    int streamVersionCursor,
  ) => _mutex.protectRead(() async {
    try {
      return await _database.getStreamEvents(
        streamPath,
        streamVersionCursor,
        _eventFetchPageSize,
      );
    } on Exception catch (cause) {
      throw EventStoreException(
        "Failed to get stream events for '$streamPath'",
        cause: cause,
      );
    }
  });

  PaginatedReader<StoredEvent> getAppliedEventReader(int localSequenceCursor) =>
      PaginatedReader(
        _readAppliedEventPage,
        initialCursor: localSequenceCursor,
      );

  Future<PaginatedResult<StoredEvent>> _readAppliedEventPage(
    int localSequenceCursor,
  ) => _mutex.protectRead(() async {
    try {
      return await _database.getLocalEvents(
        localSequenceCursor,
        _eventFetchPageSize,
      );
    } on Exception catch (cause) {
      throw EventStoreException('Failed to get local events', cause: cause);
    }
  });

  Future<GetStatisticsResult> getStatistics() => _mutex.protectRead(() async {
    try {
      return await _database.getStatistics();
    } on Exception catch (cause) {
      throw EventStoreException('Failed to get statistics', cause: cause);
    }
  });
}
