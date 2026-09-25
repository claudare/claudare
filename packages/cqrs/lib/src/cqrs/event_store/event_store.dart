import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_bundle.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:mutex/mutex.dart';

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
        final events = <BundledEvent>[];
        for (var i = 0; i < changes.events.length; i++) {
          final event = changes.events[i];
          events.add(
            BundledEvent(
              streamPath: event.streamPath,
              encodedEvent: event.encodedEvent,
              occuredAt: event.occuredAt,
            ),
          );
        }

        final saved = await _database.saveBundle(
          CommandBundle(
            commandId: commandId,
            dependency: changes.dependency,
            occuredAt: changes.occuredAt,
            events: events,
          ),
        );
        if (!saved) throw StateError('local command is out of order');
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

  Future<bool> saveBundle(CommandBundle bundle) async {
    final saved = await _mutex.protectWrite(() async {
      try {
        return await _database.saveBundle(bundle);
      } on Exception catch (cause) {
        throw EventStoreException(
          'Failed to save command bundle',
          cause: cause,
        );
      }
    });
    if (saved) _logChangesController.add(null);
    return saved;
  }

  Future<CommandBundle?> getBundle(CommandId commandId) =>
      _mutex.protectRead(() async {
        try {
          return await _database.getBundle(commandId);
        } on Exception catch (cause) {
          throw EventStoreException(
            'Failed to get command bundle $commandId',
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
