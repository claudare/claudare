import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event/stream_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:cqrs/src/cqrs/exception/replicated_command_conflict.dart';
import 'package:mutex/mutex.dart';

enum StageReplicatedCommandResult { staged, alreadyPresent }

class GetStreamInfoResult {
  final int originatingStreamVersion;

  const GetStreamInfoResult({required this.originatingStreamVersion});
}

class GetStatisticsResult {
  final int eventCount;
  final int storageSize; // bytes

  GetStatisticsResult({required this.eventCount, required this.storageSize});
}

class EventStore {
  final EventDatabase _database;
  final int _eventFetchPageSize;
  final ReadWriteMutex _mutex = ReadWriteMutex();
  final StreamController<void> _appliedChangesController =
      StreamController<void>.broadcast(sync: false);
  Future<void>? _closeFuture;

  EventStore(EventDatabase database, {int? eventFetchPageSize})
    : _database = database,
      _eventFetchPageSize =
          eventFetchPageSize ?? database.defaultEventFetchPageSize;

  Stream<void> get appliedChanges => _appliedChangesController.stream;

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await _appliedChangesController.close();
    } finally {
      await _database.close();
    }
  }

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

  Future<GetStreamInfoResult?> getStreamInfo(String streamPath) =>
      _mutex.protectRead(() async {
        try {
          final version = await _database.getStreamVersion(streamPath);
          return version == 0
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
        final streamVersions = <String, int>{};
        for (final lock in changes.locks) {
          final current = await _database.getStreamVersion(lock.streamPath);
          if (current != lock.originatingStreamVersion) {
            throw ConcurrencyProblem();
          }
          streamVersions[lock.streamPath] = current;
        }

        final commandId = CommandId(
          deviceId,
          state.appliedVersion.value(deviceId) + 1,
        );
        var localEventSequence = state.lastLocalEventSequence;
        final appliedEvents = <AppliedEvent>[];
        for (var i = 0; i < changes.events.length; i++) {
          final event = changes.events[i];
          final streamVersion = (streamVersions[event.streamPath] ?? 0) + 1;
          streamVersions[event.streamPath] = streamVersion;
          appliedEvents.add(
            AppliedEvent(
              eventId: EventId(deviceId, commandId.sequence, i),
              streamPath: event.streamPath,
              encodedEvent: event.encodedEvent,
              occuredAt: event.occuredAt,
              localSequence: ++localEventSequence,
              streamVersion: streamVersion,
            ),
          );
        }

        await _database.appendApplied(
          AppliedCommand(
            commandId: commandId,
            dependency: state.appliedVersion,
            encoded: changes.encoded,
            startedAt: changes.startedAt,
            completedAt: changes.completedAt,
            eventCount: appliedEvents.length,
            localSequence: state.lastLocalCommandSequence + 1,
          ),
          appliedEvents,
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
              streamVersions[event.streamPath] ??
              await _database.getStreamVersion(event.streamPath);
          final next = current + 1;
          streamVersions[event.streamPath] = next;
          events.add(
            AppliedEvent(
              eventId: event.eventId,
              streamPath: event.streamPath,
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

  PaginatedReader<StreamEvent> getStreamReader(String streamPath) =>
      PaginatedReader(
        (cursor) => _readStreamPage(streamPath, cursor),
        initialCursor: 0,
      );

  Future<PaginatedResult<StreamEvent>> _readStreamPage(
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

  PaginatedReader<LocalEvent> getAppliedEventReader(int localSequenceCursor) =>
      PaginatedReader(
        _readAppliedEventPage,
        initialCursor: localSequenceCursor,
      );

  Future<PaginatedResult<LocalEvent>> _readAppliedEventPage(
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

  Future<void> reset() => _mutex.protectWrite(() async {
    try {
      await _database.reset();
    } on Exception catch (cause) {
      throw EventStoreException('Failed to reset event database', cause: cause);
    }
  });
}
