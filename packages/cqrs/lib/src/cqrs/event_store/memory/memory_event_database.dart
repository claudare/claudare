import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';

/// [MemoryEventDatabase] is an in-memory implementation of [EventDatabase].
///
/// This is a reference implementation of the [EventDatabase].
/// It is slow yet correct.
class MemoryEventDatabase implements EventDatabase {
  final List<_MemoryCommand> _commands = [];
  final List<_MemoryEvent> _events = [];
  final Map<String, _MemoryPendingCommand> _pendingCommands = {};
  final Map<String, _MemoryPendingEvent> _pendingEvents = {};
  // Each stream links to zero-based indexes in _events, in stream order.
  final Map<String, List<int>> _streamVersions = {};

  MemoryEventDatabase();

  @override
  int get defaultEventFetchPageSize => 10;

  AppliedCommand _appliedCommand(_MemoryCommand command) => AppliedCommand(
    commandId: command.commandId,
    dependency: command.dependency,
    encoded: command.encoded,
    startedAt: command.startedAt,
    completedAt: command.completedAt,
    eventCount: command.eventCount,
    localSequence: command.localSequence,
  );

  ReplicatedCommand _replicatedCommand(_MemoryCommand command) =>
      _appliedCommand(command).toReplicatedCommand();

  ReplicatedCommand _replicatedPendingCommand(_MemoryPendingCommand command) =>
      ReplicatedCommand(
        commandId: command.commandId,
        dependency: command.dependency,
        encoded: command.encoded,
        startedAt: command.startedAt,
        completedAt: command.completedAt,
        eventCount: command.eventCount,
      );

  ReplicatedEvent _replicatedPendingEvent(_MemoryPendingEvent event) =>
      ReplicatedEvent(
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
    throw StateError('applied event has no stream link');
  }

  AppliedEvent _appliedEvent(int eventIndex) {
    final event = _events[eventIndex];
    final (streamPath, streamVersion) = _streamPosition(eventIndex);
    return AppliedEvent(
      eventId: event.eventId,
      streamPath: streamPath,
      encodedEvent: event.encodedEvent,
      occuredAt: event.occuredAt,
      localSequence: event.localSequence,
      streamVersion: streamVersion,
    );
  }

  VersionVector _appliedVersion() {
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
    lastLocalCommandSequence:
        _commands.isEmpty ? null : _commands.last.localSequence,
    lastLocalEventSequence: _events.isEmpty ? null : _events.last.localSequence,
    appliedVersion: _appliedVersion(),
  );

  @override
  Future<int?> getStreamVersion(String streamPath) async {
    final indexes = _streamVersions[streamPath];
    return indexes == null || indexes.isEmpty ? null : indexes.length - 1;
  }

  @override
  Future<PaginatedResult<StoredEvent>> getStreamEvents(
    String streamPath,
    int streamVersionCursor,
    int count,
  ) async {
    final indexes = _streamVersions[streamPath] ?? const <int>[];
    final events = <StoredEvent>[];
    for (
      var version = streamVersionCursor;
      version < indexes.length && events.length < count;
      version++
    ) {
      final event = _events[indexes[version]];
      events.add(
        StoredEvent(
          streamPath: streamPath,
          eventId: event.eventId,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          localSequence: event.localSequence,
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
  Future<PaginatedResult<StoredEvent>> getLocalEvents(
    int localSequenceCursor,
    int count,
  ) async {
    final events = <StoredEvent>[];
    for (
      var index = 0;
      index < _events.length && events.length < count;
      index++
    ) {
      final event = _events[index];
      if (event.localSequence < localSequenceCursor) continue;
      final (streamPath, version) = _streamPosition(index);
      events.add(
        StoredEvent(
          eventId: event.eventId,
          streamPath: streamPath,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          localSequence: event.localSequence,
          version: version,
        ),
      );
    }
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.localSequence + 1,
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
  Future<ReplicatedCommand?> getAppliedCommand(CommandId commandId) async {
    for (final command in _commands) {
      if (command.commandId == commandId) return _replicatedCommand(command);
    }
    return null;
  }

  @override
  Future<ReplicatedCommand?> getPendingCommand(CommandId commandId) async {
    final command = _pendingCommands[commandId.toString()];
    return command == null ? null : _replicatedPendingCommand(command);
  }

  @override
  Future<ReplicatedEvent?> getAppliedEvent(EventId eventId) async {
    for (var index = 0; index < _events.length; index++) {
      if (_events[index].eventId == eventId) {
        return _appliedEvent(index).toReplicatedEvent();
      }
    }
    return null;
  }

  @override
  Future<ReplicatedEvent?> getPendingEvent(EventId eventId) async {
    final event = _pendingEvents[eventId.toString()];
    return event == null ? null : _replicatedPendingEvent(event);
  }

  @override
  Future<List<AppliedCommand>> getAppliedCommands(
    int localSequenceCursor,
    int count,
  ) async => _commands
      .where((command) => command.localSequence >= localSequenceCursor)
      .take(count)
      .map(_appliedCommand)
      .toList(growable: false);

  @override
  Future<List<AppliedEvent>> getAppliedEvents(CommandId commandId) async => [
    for (var index = 0; index < _events.length; index++)
      if (_events[index].eventId.commandId == commandId) _appliedEvent(index),
  ]..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));

  void _validateApplied(
    ReplicatedCommand command,
    List<ReplicatedEvent> events,
  ) {
    final frontier = _appliedVersion();
    if (!frontier.contains(command.dependency)) {
      throw StateError('command dependency is not ready');
    }
    if (frontier.value(command.commandId.deviceId) + 1 !=
        command.commandId.sequence) {
      throw StateError('command id is out of order');
    }
    if (_commands.any((stored) => stored.commandId == command.commandId)) {
      throw StateError('command id already applied');
    }
    if (events.length != command.eventCount) {
      throw StateError('applied event count does not match command');
    }

    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.eventId.commandId != command.commandId ||
          event.eventId.index != i) {
        throw StateError('event identity is invalid');
      }
    }
  }

  void _appendValidated(
    ReplicatedCommand command,
    List<ReplicatedEvent> events,
  ) {
    _commands.add(
      _MemoryCommand(
        commandId: command.commandId,
        dependency: command.dependency,
        encoded: command.encoded,
        startedAt: command.startedAt,
        completedAt: command.completedAt,
        eventCount: command.eventCount,
        localSequence: _commands.length,
      ),
    );
    for (final event in events) {
      final eventIndex = _events.length;
      _events.add(
        _MemoryEvent(
          eventId: event.eventId,
          encodedEvent: event.encodedEvent,
          occuredAt: event.occuredAt,
          localSequence: _events.length,
        ),
      );
      _streamVersions.putIfAbsent(event.streamPath, () => []).add(eventIndex);
    }
  }

  @override
  Future<void> appendApplied(
    ReplicatedCommand command,
    List<ReplicatedEvent> events,
  ) async {
    _validateApplied(command, events);
    _appendValidated(command, events);
  }

  @override
  Future<void> stagePendingCommand(ReplicatedCommand command) async {
    final key = command.commandId.toString();
    if (_pendingCommands.containsKey(key)) {
      throw StateError('command id is already pending');
    }
    _pendingCommands[key] = _MemoryPendingCommand(
      commandId: command.commandId,
      dependency: command.dependency,
      encoded: command.encoded,
      startedAt: command.startedAt,
      completedAt: command.completedAt,
      eventCount: command.eventCount,
    );
  }

  @override
  Future<void> stagePendingEvents(List<ReplicatedEvent> events) async {
    final keys = <String>{};
    for (final event in events) {
      final key = event.eventId.toString();
      if (_pendingEvents.containsKey(key) || !keys.add(key)) {
        throw StateError('event id is already pending');
      }
    }
    for (final event in events) {
      _pendingEvents[event.eventId.toString()] = _MemoryPendingEvent(
        streamPath: event.streamPath,
        eventId: event.eventId,
        encodedEvent: event.encodedEvent,
        occuredAt: event.occuredAt,
      );
    }
  }

  @override
  Future<bool> promotePending(CommandId commandId) async {
    final pending = _pendingCommands[commandId.toString()];
    if (pending == null) return false;
    final command = _replicatedPendingCommand(pending);
    final frontier = _appliedVersion();
    if (!frontier.contains(command.dependency) ||
        frontier.value(commandId.deviceId) + 1 != commandId.sequence) {
      return false;
    }
    final events =
        _pendingEvents.values
            .map(_replicatedPendingEvent)
            .where((event) => event.eventId.commandId == commandId)
            .toList()
          ..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));
    if (events.length != command.eventCount) return false;
    for (var i = 0; i < events.length; i++) {
      if (events[i].eventId.index != i) return false;
    }
    _validateApplied(command, events);
    _appendValidated(command, events);
    _pendingCommands.remove(commandId.toString());
    for (final event in events) {
      _pendingEvents.remove(event.eventId.toString());
    }
    return true;
  }
}

class _MemoryCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;
  final int localSequence;

  _MemoryCommand({
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
}

class _MemoryPendingCommand {
  final CommandId commandId;
  final VersionVector dependency;
  final EncodedCommand encoded;
  final DateTime startedAt;
  final DateTime completedAt;
  final int eventCount;

  _MemoryPendingCommand({
    required this.commandId,
    required this.dependency,
    required this.encoded,
    required this.startedAt,
    required this.completedAt,
    required this.eventCount,
  }) {
    if (eventCount <= 0) {
      throw const FormatException(
        'applied commands must produce at least one event',
      );
    }
  }
}

class _MemoryEvent {
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;
  final int localSequence;

  const _MemoryEvent({
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
    required this.localSequence,
  });
}

class _MemoryPendingEvent {
  final String streamPath;
  final EventId eventId;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const _MemoryPendingEvent({
    required this.streamPath,
    required this.eventId,
    required this.encodedEvent,
    required this.occuredAt,
  });
}
