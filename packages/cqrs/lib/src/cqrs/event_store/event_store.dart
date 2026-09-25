import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/log_command.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:cqrs/src/cqrs/exception/staged_command_conflict.dart';
import 'package:mutex/mutex.dart';

enum StageCommandResult { staged, alreadyPresent }

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
  final StreamController<void> _logChangesController =
      StreamController<void>.broadcast(sync: false);

  EventStore(EventDatabase database, {int? eventFetchPageSize})
    : _database = database,
      _eventFetchPageSize =
          eventFetchPageSize ?? database.defaultEventFetchPageSize;

  Stream<void> get logChanges => _logChangesController.stream;

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
        if (!state.logVersion.contains(changes.dependency)) {
          throw StateError('command dependency is not in the log');
        }
        for (final lock in changes.locks) {
          final current = await _database.getStreamVersion(lock.streamPath);
          if (current != lock.originatingStreamVersion) {
            throw ConcurrencyProblem();
          }
        }

        final commandId = CommandId(
          deviceId,
          state.logVersion.value(deviceId) + 1,
        );
        final events = <StagedEvent>[];
        for (var i = 0; i < changes.events.length; i++) {
          final event = changes.events[i];
          events.add(
            StagedEvent(
              eventId: EventId(deviceId, commandId.sequence, i),
              streamPath: event.streamPath,
              encodedEvent: event.encodedEvent,
              occuredAt: event.occuredAt,
            ),
          );
        }

        await _database.appendLog(
          StagedCommand(
            commandId: commandId,
            dependency: changes.dependency,
            occuredAt: changes.occuredAt,
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
    _logChangesController.add(null);
  }

  Future<StageCommandResult> stageCommand(StagedCommand command) =>
      _mutex.protectWrite(() async {
        try {
          final commandId = command.commandId;
          final existing =
              await _database.getLogCommand(commandId) ??
              await _database.getStagedCommand(commandId);
          if (existing != null) {
            if (stagedCommandsEqual(existing, command)) {
              return StageCommandResult.alreadyPresent;
            }
            throw StagedCommandConflict(commandId);
          }
          await _database.stageCommand(command);
          return StageCommandResult.staged;
        } on StagedCommandConflict {
          rethrow;
        } on Exception catch (cause) {
          throw EventStoreException('Failed to stage command', cause: cause);
        }
      });

  Future<StageCommandResult> stageEvents(List<StagedEvent> events) =>
      _mutex.protectWrite(() async {
        try {
          final unique = <EventId, StagedEvent>{};
          for (final event in events) {
            final duplicate = unique[event.eventId];
            if (duplicate != null && duplicate != event) {
              throw StagedCommandConflict(event.eventId);
            }
            unique[event.eventId] = event;
          }
          final staged = <StagedEvent>[];
          for (final event in unique.values) {
            final existing =
                await _database.getLogEvent(event.eventId) ??
                await _database.getStagedEvent(event.eventId);
            if (existing == null) {
              staged.add(event);
            } else if (existing != event) {
              throw StagedCommandConflict(event.eventId);
            }
          }
          if (staged.isEmpty) return StageCommandResult.alreadyPresent;
          await _database.stageEvents(staged);
          return StageCommandResult.staged;
        } on StagedCommandConflict {
          rethrow;
        } on Exception catch (cause) {
          throw EventStoreException('Failed to stage events', cause: cause);
        }
      });

  Future<bool> promoteStaged(CommandId commandId) async {
    final promoted = await _mutex.protectWrite(() async {
      try {
        return await _database.promoteStaged(commandId);
      } on Exception catch (cause) {
        throw EventStoreException(
          'Failed to promote staged command $commandId',
          cause: cause,
        );
      }
    });
    if (promoted) _logChangesController.add(null);
    return promoted;
  }

  Future<List<LogCommand>> getLogCommands(int fromPosition) =>
      _mutex.protectRead(() async {
        try {
          return await _database.getLogCommands(
            fromPosition,
            _eventFetchPageSize,
          );
        } on Exception catch (cause) {
          throw EventStoreException('Failed to get log commands', cause: cause);
        }
      });

  Future<List<LogEvent>> getLogEventsForCommand(CommandId commandId) =>
      _mutex.protectRead(() async {
        try {
          return await _database.getLogEventsForCommand(commandId);
        } on Exception catch (cause) {
          throw EventStoreException(
            'Failed to get log events for $commandId',
            cause: cause,
          );
        }
      });

  PaginatedReader<LogEvent> getStreamReader(
    String streamPath, {
    int fromVersion = 0,
  }) => PaginatedReader(
    (cursor) => _readStreamPage(streamPath, cursor),
    initialCursor: fromVersion,
  );

  Future<PaginatedResult<LogEvent>> _readStreamPage(
    String streamPath,
    int fromVersion,
  ) => _mutex.protectRead(() async {
    try {
      return await _database.getStreamEvents(
        streamPath,
        fromVersion,
        _eventFetchPageSize,
      );
    } on Exception catch (cause) {
      throw EventStoreException(
        "Failed to get stream events for '$streamPath'",
        cause: cause,
      );
    }
  });

  PaginatedReader<LogEvent> getLogEventReader(int fromPosition) =>
      PaginatedReader(_readLogEventPage, initialCursor: fromPosition);

  Future<PaginatedResult<LogEvent>> _readLogEventPage(int fromPosition) =>
      _mutex.protectRead(() async {
        try {
          return await _database.getLogEvents(
            fromPosition,
            _eventFetchPageSize,
          );
        } on Exception catch (cause) {
          throw EventStoreException('Failed to get log events', cause: cause);
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
