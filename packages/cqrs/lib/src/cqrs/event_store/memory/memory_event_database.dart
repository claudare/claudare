import 'package:common/common.dart';
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
  final Map<String, _MemoryStagedCommand> _stagedCommands = {};
  final Map<String, _MemoryStagedEvent> _stagedEvents = {};
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

  StagedCommand _stagedCommand(_MemoryStagedCommand command) => StagedCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    occuredAt: command.occuredAt,
    eventCount: command.eventCount,
  );

  StagedEvent _stagedEvent(_MemoryStagedEvent event) => StagedEvent(
    eventId: event.eventId,
    streamPath: event.streamPath,
    encodedEvent: event.encodedEvent,
    occuredAt: event.occuredAt,
  );

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
  Future<StagedCommand?> getLogCommand(CommandId commandId) async {
    for (final command in _commands) {
      if (command.commandId == commandId) {
        return _stagedCommandFromLog(command);
      }
    }
    return null;
  }

  @override
  Future<StagedCommand?> getStagedCommand(CommandId commandId) async {
    final command = _stagedCommands[commandId.toString()];
    return command == null ? null : _stagedCommand(command);
  }

  @override
  Future<StagedEvent?> getLogEvent(EventId eventId) async {
    for (var index = 0; index < _events.length; index++) {
      if (_events[index].eventId == eventId) {
        return _logEvent(index).toStagedEvent();
      }
    }
    return null;
  }

  @override
  Future<StagedEvent?> getStagedEvent(EventId eventId) async {
    final event = _stagedEvents[eventId.toString()];
    return event == null ? null : _stagedEvent(event);
  }

  @override
  Future<List<LogCommand>> getLogCommands(int fromPosition, int count) async =>
      _commands
          .where((command) => command.logPosition >= fromPosition)
          .take(count)
          .map(_logCommand)
          .toList(growable: false);

  @override
  Future<List<LogEvent>> getLogEventsForCommand(CommandId commandId) async => [
    for (var index = 0; index < _events.length; index++)
      if (_events[index].eventId.commandId == commandId) _logEvent(index),
  ]..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));

  void _validateLog(StagedCommand command, List<StagedEvent> events) {
    final frontier = _logVersion();
    if (!frontier.contains(command.dependency)) {
      throw StateError('command dependency is not ready');
    }
    if (frontier.value(command.commandId.deviceId) + 1 !=
        command.commandId.sequence) {
      throw StateError('command id is out of order');
    }
    if (_commands.any(
      (logCommand) => logCommand.commandId == command.commandId,
    )) {
      throw StateError('command id is already in the log');
    }
    if (events.length != command.eventCount) {
      throw StateError('log event count does not match command');
    }

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.eventId.commandId != command.commandId ||
          event.eventId.index != i) {
        throw StateError('event identity is invalid');
      }
    }
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
  Future<void> appendLog(
    StagedCommand command,
    List<StagedEvent> events,
  ) async {
    _validateLog(command, events);
    _appendValidated(command, events);
  }

  @override
  Future<void> stageCommand(StagedCommand command) async {
    final key = command.commandId.toString();
    if (_stagedCommands.containsKey(key)) {
      throw StateError('command id is already staged');
    }
    _stagedCommands[key] = _MemoryStagedCommand(
      commandId: command.commandId,
      dependency: command.dependency,
      occuredAt: command.occuredAt,
      eventCount: command.eventCount,
    );
  }

  @override
  Future<void> stageEvents(List<StagedEvent> events) async {
    final keys = <String>{};
    for (final event in events) {
      final key = event.eventId.toString();
      if (_stagedEvents.containsKey(key) || !keys.add(key)) {
        throw StateError('event id is already staged');
      }
    }
    for (final event in events) {
      _stagedEvents[event.eventId.toString()] = _MemoryStagedEvent(
        streamPath: event.streamPath,
        eventId: event.eventId,
        encodedEvent: event.encodedEvent,
        occuredAt: event.occuredAt,
      );
    }
  }

  @override
  Future<bool> promoteStaged(CommandId commandId) async {
    final staged = _stagedCommands[commandId.toString()];
    if (staged == null) return false;
    final command = _stagedCommand(staged);
    final frontier = _logVersion();
    if (!frontier.contains(command.dependency) ||
        frontier.value(commandId.deviceId) + 1 != commandId.sequence) {
      return false;
    }
    final events =
        _stagedEvents.values
            .map(_stagedEvent)
            .where((event) => event.eventId.commandId == commandId)
            .toList()
          ..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));
    if (events.length != command.eventCount) return false;
    for (var i = 0; i < events.length; i++) {
      if (events[i].eventId.index != i) return false;
    }
    _validateLog(command, events);
    _appendValidated(command, events);
    _stagedCommands.remove(commandId.toString());
    for (final event in events) {
      _stagedEvents.remove(event.eventId.toString());
    }
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

class _MemoryStagedCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final DateTime occuredAt;
  final int eventCount;

  _MemoryStagedCommand({
    required this.commandId,
    required this.dependency,
    required this.occuredAt,
    required this.eventCount,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'staged commands must produce at least one event',
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

class _MemoryStagedEvent {
  final String streamPath;
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const _MemoryStagedEvent({
    required this.streamPath,
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
  });
}
