import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/applied_command.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/replicated_command.dart';
import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/replicated_event.dart';
import 'package:cqrs/src/cqrs/event/local_event.dart';
import 'package:cqrs/src/cqrs/event/stream_event.dart';
import 'package:cqrs/src/cqrs/command/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';

class MemoryEventDatabase implements EventDatabase {
  final List<AppliedCommand> _commands = [];
  final List<AppliedEvent> _events = [];
  final Map<CommandId, (ReplicatedCommand, int)> _pendingCommands = {};
  final Map<EventId, (ReplicatedEvent, int)> _pendingEvents = {};
  int _nextPendingCommandSequence = -1;
  int _nextPendingEventSequence = -1;
  final Map<String, int> _streamVersions = {};
  final void Function()? _onChange;

  MemoryEventDatabase({void Function()? onChange}) : _onChange = onChange;

  @override
  int get defaultEventFetchPageSize => 10;

  List<AppliedCommand> get testAppliedCommands => List.unmodifiable(_commands);
  List<AppliedEvent> get testAppliedEvents => List.unmodifiable(_events);
  List<ReplicatedCommand> get testPendingCommands =>
      List.unmodifiable(_pendingCommands.values.map((entry) => entry.$1));
  List<ReplicatedEvent> get testPendingEvents =>
      List.unmodifiable(_pendingEvents.values.map((entry) => entry.$1));
  List<int> get testPendingCommandLocalSequences =>
      List.unmodifiable(_pendingCommands.values.map((entry) => entry.$2));
  List<int> get testPendingEventLocalSequences =>
      List.unmodifiable(_pendingEvents.values.map((entry) => entry.$2));

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
        _commands.isEmpty ? 0 : _commands.last.localSequence,
    lastLocalEventSequence: _events.isEmpty ? 0 : _events.last.localSequence,
    appliedVersion: _appliedVersion(),
  );

  @override
  Future<int> getStreamVersion(String streamPath) async =>
      _streamVersions[streamPath] ?? 0;

  @override
  Future<PaginatedResult<StreamEvent>> getStreamEvents(
    String streamPath,
    int streamVersionCursor,
    int count,
  ) async {
    final events = _events
        .where(
          (event) =>
              event.streamPath == streamPath &&
              event.streamVersion > streamVersionCursor,
        )
        .take(count)
        .map(
          (event) => StreamEvent(
            commandId: event.eventId.commandId,
            encodedEvent: event.encodedEvent,
            occuredAt: event.occuredAt,
            streamVersion: event.streamVersion,
          ),
        )
        .toList(growable: false);
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.streamVersion,
    );
  }

  @override
  Future<PaginatedResult<LocalEvent>> getLocalEvents(
    int localSequenceCursor,
    int count,
  ) async {
    final events = _events
        .where((event) => event.localSequence > localSequenceCursor)
        .take(count)
        .map(
          (event) => LocalEvent(
            streamPath: event.streamPath,
            encodedEvent: event.encodedEvent,
            occuredAt: event.occuredAt,
            localSequence: event.localSequence,
          ),
        )
        .toList(growable: false);
    return PaginatedResult(
      data: events,
      next: events.isEmpty ? null : events.last.localSequence,
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
      if (command.commandId == commandId) return command.toReplicatedCommand();
    }
    return null;
  }

  @override
  Future<ReplicatedCommand?> getPendingCommand(CommandId commandId) async =>
      _pendingCommands[commandId]?.$1;

  @override
  Future<ReplicatedEvent?> getAppliedEvent(EventId eventId) async {
    for (final event in _events) {
      if (event.eventId == eventId) return event.toReplicatedEvent();
    }
    return null;
  }

  @override
  Future<ReplicatedEvent?> getPendingEvent(EventId eventId) async =>
      _pendingEvents[eventId]?.$1;

  @override
  Future<List<AppliedCommand>> getAppliedCommands(
    int localSequenceCursor,
    int count,
  ) async => _commands
      .where((command) => command.localSequence > localSequenceCursor)
      .take(count)
      .toList(growable: false);

  @override
  Future<List<AppliedEvent>> getAppliedEvents(CommandId commandId) async =>
      _events
          .where((event) => event.eventId.commandId == commandId)
          .toList(growable: false)
        ..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));

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
      AppliedCommand.fromReplicatedCommand(
        command,
        localSequence: _commands.length + 1,
      ),
    );
    for (final event in events) {
      final version = (_streamVersions[event.streamPath] ?? 0) + 1;
      final applied = AppliedEvent.fromReplicatedEvent(
        event,
        localSequence: _events.length + 1,
        streamVersion: version,
      );
      _events.add(applied);
      _streamVersions[event.streamPath] = version;
    }
  }

  @override
  Future<void> appendApplied(
    ReplicatedCommand command,
    List<ReplicatedEvent> events,
  ) async {
    _validateApplied(command, events);
    _appendValidated(command, events);
    _onChange?.call();
  }

  @override
  Future<void> stagePendingCommand(ReplicatedCommand command) async {
    if (_pendingCommands.containsKey(command.commandId)) {
      throw StateError('command id is already pending');
    }
    _pendingCommands[command.commandId] = (
      command,
      _nextPendingCommandSequence--,
    );
  }

  @override
  Future<void> stagePendingEvents(List<ReplicatedEvent> events) async {
    for (final event in events) {
      if (_pendingEvents.containsKey(event.eventId)) {
        throw StateError('event id is already pending');
      }
    }
    for (final event in events) {
      _pendingEvents[event.eventId] = (event, _nextPendingEventSequence--);
    }
  }

  @override
  Future<bool> promotePending(CommandId commandId) async {
    final command = _pendingCommands[commandId]?.$1;
    if (command == null) return false;
    final frontier = _appliedVersion();
    if (!frontier.contains(command.dependency) ||
        frontier.value(commandId.deviceId) + 1 != commandId.sequence) {
      return false;
    }
    final events =
        _pendingEvents.values
            .map((entry) => entry.$1)
            .where((event) => event.eventId.commandId == commandId)
            .toList()
          ..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));
    if (events.length != command.eventCount) return false;
    for (var i = 0; i < events.length; i++) {
      if (events[i].eventId.index != i) return false;
    }
    _validateApplied(command, events);
    _appendValidated(command, events);
    _pendingCommands.remove(commandId);
    for (final event in events) {
      _pendingEvents.remove(event.eventId);
    }
    _onChange?.call();
    return true;
  }
}
