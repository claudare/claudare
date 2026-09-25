import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_bundle.dart';
import 'package:cqrs/src/cqrs/command/log_command.dart';
import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';
import 'package:cqrs/src/cqrs/event/log_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';

/// [MemoryEventDatabase] is an in-memory implementation of [EventDatabase].
///
/// This is a reference implementation of the [EventDatabase].
/// It is slow yet correct.
class MemoryEventDatabase implements EventDatabase {
  final List<_MemoryLogCommand> _commands = [];
  final List<_MemoryLogEvent> _events = [];
  // Each stream links to zero-based indexes in _events, in stream order.
  final Map<String, List<int>> _streamVersions = {};

  MemoryEventDatabase();

  @override
  int get defaultEventFetchPageSize => 10;

  LogCommand _logCommand(_MemoryLogCommand command) => LogCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    occuredAt: command.occuredAt,
    eventCount: command.eventCount,
    logPosition: command.logPosition,
  );

  StagedCommand _stagedCommandFromLog(_MemoryLogCommand command) =>
      _logCommand(command).toStagedCommand();

  (String, int) _streamPosition(int eventIndex) {
    for (final entry in _streamVersions.entries) {
      final position = entry.value.indexOf(eventIndex);
      if (position >= 0) return (entry.key, position);
    }
    throw StateError('log event has no stream link');
  }

  LogEvent _logEvent(int eventIndex) {
    final event = _events[eventIndex];
    final (streamPath, streamVersion) = _streamPosition(eventIndex);
    return LogEvent(
      eventId: event.eventId,
      streamPath: streamPath,
      encodedEvent: event.encodedEvent,
      occuredAt: event.occuredAt,
      logPosition: event.logPosition,
      version: streamVersion,
    );
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
  Future<EventDatabaseState> getState() async => EventDatabaseState(
    lastCommandLogPosition:
        _commands.isEmpty ? null : _commands.last.logPosition,
    lastEventLogPosition: _events.isEmpty ? null : _events.last.logPosition,
    logVersion: _logVersion(),
  );

  @override
  Future<int?> getStreamVersion(String streamPath) async {
    final indexes = _streamVersions[streamPath];
    return indexes == null || indexes.isEmpty ? null : indexes.length - 1;
  }

  @override
  Future<PaginatedResult<LogEvent>> getStreamEvents(
    String streamPath,
    int fromVersion,
    int count,
  ) async {
    final indexes = _streamVersions[streamPath] ?? const <int>[];
    final events = <LogEvent>[];
    for (
      var version = fromVersion;
      version < indexes.length && events.length < count;
      version++
    ) {
      final event = _events[indexes[version]];
      events.add(
        LogEvent(
          streamPath: streamPath,
          eventId: event.eventId,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          logPosition: event.logPosition,
          version: version,
        ),
      );
    }
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.version + 1,
    );
  }

  @override
  Future<PaginatedResult<LogEvent>> getLogEvents(
    int fromPosition,
    int count,
  ) async {
    final events = <LogEvent>[];
    for (
      var index = 0;
      index < _events.length && events.length < count;
      index++
    ) {
      final event = _events[index];
      if (event.logPosition < fromPosition) continue;
      final (streamPath, version) = _streamPosition(index);
      events.add(
        LogEvent(
          eventId: event.eventId,
          streamPath: streamPath,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          logPosition: event.logPosition,
          version: version,
        ),
      );
    }
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.logPosition + 1,
    );
  }

  @override
  Future<GetStatisticsResult> getStatistics() async => GetStatisticsResult(
    eventCount: _events.length,
    storageSize: _events.fold(
      0,
      (total, event) => total + event.encodedEvent.bytes.length,
    ),
  );

  @override
  Future<CommandBundle?> getBundle(CommandId commandId) async {
    for (final command in _commands) {
      if (command.commandId == commandId) {
        return CommandBundle(
          command: _stagedCommandFromLog(command),
          events: [
            for (var index = 0; index < _events.length; index++)
              if (_events[index].eventId.commandId == commandId)
                _logEvent(index).toStagedEvent(),
          ],
        );
      }
    }
    return null;
  }

  bool _isReady(StagedCommand command) {
    final frontier = _logVersion();
    return frontier.contains(command.dependency) &&
        frontier.value(command.commandId.deviceId) + 1 ==
            command.commandId.sequence;
  }

  void _appendValidated(StagedCommand command, List<StagedEvent> events) {
    _commands.add(
      _MemoryLogCommand(
        commandId: command.commandId,
        dependency: command.dependency,
        occuredAt: command.occuredAt,
        eventCount: command.eventCount,
        logPosition: _commands.length,
      ),
    );
    for (final event in events) {
      final eventIndex = _events.length;
      _events.add(
        _MemoryLogEvent(
          eventId: event.eventId,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          logPosition: _events.length,
        ),
      );
      _streamVersions.putIfAbsent(event.streamPath, () => []).add(eventIndex);
    }
  }

  @override
  Future<bool> saveBundle(CommandBundle bundle) async {
    if (!bundle.isValid) throw ArgumentError('invalid command bundle');
    if (!_isReady(bundle.command)) return false;
    _appendValidated(bundle.command, bundle.events);
    return true;
  }
}

class _MemoryLogCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final DateTime occuredAt;
  final int eventCount;
  final int logPosition;

  _MemoryLogCommand({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
    required this.eventCount,
    required this.logPosition,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'log commands must produce at least one event',
      );
    }
  }
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
