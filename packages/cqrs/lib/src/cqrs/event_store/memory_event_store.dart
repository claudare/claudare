import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_bundle.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';
import 'package:mutex/mutex.dart';

/// [MemoryEventStore] is an in-memory implementation of [EventStore].
///
/// This is a reference implementation of the [EventStore].
/// It is slow yet correct.
class MemoryEventStore implements EventStore {
  final List<_MemoryLogCommand> _commands = [];
  final List<_MemoryLogEvent> _events = [];
  // Each stream links to zero-based indexes in _events, in stream order.
  final Map<String, List<int>> _streamVersions = {};

  final int _eventFetchPageSize;
  final ReadWriteMutex _mutex = ReadWriteMutex();

  MemoryEventStore({int eventFetchPageSize = 10})
    : _eventFetchPageSize = eventFetchPageSize {
    if (eventFetchPageSize <= 0) {
      throw ArgumentError.value(eventFetchPageSize, 'eventFetchPageSize');
    }
  }

  Future<T> _read<T>(String message, T Function() action) =>
      _mutex.protectRead(() async => _guard(message, action));

  Future<T> _write<T>(String message, T Function() action) =>
      _mutex.protectWrite(() async => _guard(message, action));

  T _guard<T>(String message, T Function() action) {
    try {
      return action();
    } on ConcurrencyProblem {
      rethrow;
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(
        EventStoreException(message, cause: cause),
        stackTrace,
      );
    }
  }

  (String, int) _streamPosition(int eventIndex) {
    for (final entry in _streamVersions.entries) {
      final position = entry.value.indexOf(eventIndex);
      if (position >= 0) return (entry.key, position);
    }
    throw StateError('log event has no stream link');
  }

  VersionVector _logVersion() {
    final values = <int, int>{};
    for (final command in _commands) {
      final id = command.commandId;
      final current = values[id.deviceId] ?? 0;
      if (id.sequence > current) values[id.deviceId] = id.sequence;
    }
    return VersionVector(values);
  }

  @override
  Future<EventDatabaseState> getState() =>
      _read('Failed to get state', _getState);

  EventDatabaseState _getState() => EventDatabaseState(
    lastCommandLogPosition:
        _commands.isEmpty ? null : _commands.last.logPosition,
    lastEventLogPosition: _events.isEmpty ? null : _events.last.logPosition,
    logVersion: _logVersion(),
  );

  @override
  Future<int?> getStreamVersion(String streamPath) => _read(
    "Failed to get stream version for '$streamPath'",
    () => _getStreamVersion(streamPath),
  );

  int? _getStreamVersion(String streamPath) {
    final indexes = _streamVersions[streamPath];
    return indexes == null || indexes.isEmpty ? null : indexes.length - 1;
  }

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
  ) => _read('Failed to get stream events', () {
    if (fromVersion < 0) {
      throw ArgumentError('fromVersion must be non-negative');
    }
    final indexes = _streamVersions[streamPath] ?? const <int>[];
    final events = <StoredEvent>[];
    for (
      var version = fromVersion;
      version < indexes.length && events.length < _eventFetchPageSize;
      version++
    ) {
      final event = _events[indexes[version]];
      events.add(
        StoredEvent(
          streamPath: streamPath,
          eventId: event.eventId,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          position: event.logPosition,
          version: version,
        ),
      );
    }
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.version + 1,
    );
  });

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) =>
      _read('Failed to get log events', () {
        if (fromPosition < 0) {
          throw ArgumentError('fromPosition must be non-negative');
        }
        final events = <StoredEvent>[];
        for (
          var index = 0;
          index < _events.length && events.length < _eventFetchPageSize;
          index++
        ) {
          final event = _events[index];
          if (event.logPosition < fromPosition) continue;
          final (streamPath, version) = _streamPosition(index);
          events.add(
            StoredEvent(
              eventId: event.eventId,
              streamPath: streamPath,
              encodedEvent: event.encodedEvent,
              occuredAt: event.occuredAt,
              position: event.logPosition,
              version: version,
            ),
          );
        }
        return PaginatedResult(
          data: events,
          next: events.isEmpty ? null : events.last.position + 1,
        );
      });

  @override
  Future<GetStatisticsResult> getStatistics() => _read(
    'Failed to get statistics',
    () => GetStatisticsResult(
      eventCount: _events.length,
      storageSize: _events.fold(
        0,
        (total, event) => total + event.encodedEvent.bytes.length,
      ),
    ),
  );

  @override
  Future<CommandBundle?> getBundle(CommandId commandId) =>
      _read('Failed to get command bundle $commandId', () {
        for (final command in _commands) {
          if (command.commandId == commandId) {
            return CommandBundle(
              commandId: command.commandId,
              dependency: command.dependency,
              occuredAt: command.occuredAt,
              events: [
                for (var index = 0; index < _events.length; index++)
                  if (_events[index].eventId.commandId == commandId)
                    BundledEvent(
                      streamPath: _streamPosition(index).$1,
                      encodedEvent: _events[index].encodedEvent,
                      occuredAt: _events[index].occuredAt,
                    ),
              ],
            );
          }
        }
        return null;
      });

  bool _isReady(CommandBundle bundle) {
    final frontier = _logVersion();
    return frontier.contains(bundle.dependency) &&
        frontier.value(bundle.commandId.deviceId) + 1 ==
            bundle.commandId.sequence;
  }

  void _appendValidated(CommandBundle bundle) {
    _commands.add(
      _MemoryLogCommand(
        commandId: bundle.commandId,
        dependency: bundle.dependency,
        occuredAt: bundle.occuredAt,
        logPosition: _commands.length,
      ),
    );
    for (final (index, event) in bundle.events.indexed) {
      final eventIndex = _events.length;
      _events.add(
        _MemoryLogEvent(
          eventId: EventId(
            bundle.commandId.deviceId,
            bundle.commandId.sequence,
            index,
          ),
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          logPosition: _events.length,
        ),
      );
      _streamVersions.putIfAbsent(event.streamPath, () => []).add(eventIndex);
    }
  }

  @override
  Future<bool> saveBundle(CommandBundle bundle) =>
      _write('Failed to save command bundle', () => _saveBundle(bundle));

  @override
  Future<void> saveChanges(CommandChanges changes) =>
      _write('Failed to append command batch', () {
        const deviceId = 0;
        if (changes.events.isEmpty) return;
        if (!changes.isValid()) {
          throw ArgumentError('every appended event must have one stream lock');
        }
        final state = _getState();
        if (!state.logVersion.contains(changes.dependency)) {
          throw StateError('command dependency is not in the log');
        }
        for (final lock in changes.locks) {
          final current = _getStreamVersion(lock.streamPath);
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

        final saved = _saveBundle(
          CommandBundle(
            commandId: commandId,
            dependency: changes.dependency,
            occuredAt: changes.occuredAt,
            events: events,
          ),
        );
        if (!saved) throw StateError('local command is out of order');
      });

  bool _saveBundle(CommandBundle bundle) {
    if (!bundle.isValid) throw ArgumentError('invalid command bundle');
    if (!_isReady(bundle)) return false;
    _appendValidated(bundle);
    return true;
  }
}

class _MemoryLogCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final DateTime occuredAt;
  final int logPosition;

  _MemoryLogCommand({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
    required this.logPosition,
  });
}

class _MemoryLogEvent {
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int logPosition;

  const _MemoryLogEvent({
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.logPosition,
  });
}
