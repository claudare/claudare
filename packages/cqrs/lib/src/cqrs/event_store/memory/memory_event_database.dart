import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/event/stored_event_command_read.dart';
import 'package:cqrs/src/cqrs/event/stored_event_projection_read.dart';
import 'package:cqrs/src/cqrs/event_store/command_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/event_store/event_id.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/event_store/paginated_read_result.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';

class MemoryEventDatabase implements EventDatabase {
  final List<AppliedCommand> _commands = [];
  final List<AppliedEvent> _events = [];
  final Map<CommandId, ReplicatedCommand> _pendingCommands = {};
  final Map<EventId, ReplicatedEvent> _pendingEvents = {};
  final Map<String, int> _streamVersions = {};
  final void Function()? _onChange;

  MemoryEventDatabase({void Function()? onChange}) : _onChange = onChange;

  @override
  int get defaultEventFetchPageSize => 10;

  List<AppliedCommand> get testAppliedCommands => List.unmodifiable(_commands);
  List<AppliedEvent> get testAppliedEvents => List.unmodifiable(_events);
  List<ReplicatedCommand> get testPendingCommands =>
      List.unmodifiable(_pendingCommands.values);
  List<ReplicatedEvent> get testPendingEvents =>
      List.unmodifiable(_pendingEvents.values);

  @override
  Future<void> migrate() async {}

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
  Future<int> getStreamVersion(String streamId) async =>
      _streamVersions[streamId] ?? 0;

  @override
  Future<PaginatedResult<StoredEventCommandRead>> getStreamEvents(
    String streamId,
    int streamVersionCursor,
    int count,
  ) async {
    final events = _events
        .where(
          (event) =>
              event.streamId == streamId &&
              event.streamVersion > streamVersionCursor,
        )
        .take(count)
        .map(
          (event) => StoredEventCommandRead(
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
  Future<PaginatedResult<StoredEventProjectionRead>> getLocalEvents(
    PatternFilter patternFilter,
    int localSequenceCursor,
    int count,
  ) async {
    final events = _events
        .where(
          (event) =>
              event.localSequence > localSequenceCursor &&
              patternFilter.doesMatchPath(event.streamId),
        )
        .take(count)
        .map(
          (event) => StoredEventProjectionRead(
            streamId: event.streamId,
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
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) async {
    final matching = _events.where(
      (event) => patternFilter.doesMatchPath(event.streamId),
    );
    return GetLocalLastEventResult(
      localSequence: matching.isEmpty ? 0 : matching.last.localSequence,
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
      _pendingCommands[commandId];

  @override
  Future<ReplicatedEvent?> getAppliedEvent(EventId eventId) async {
    for (final event in _events) {
      if (event.eventId == eventId) return event.toReplicatedEvent();
    }
    return null;
  }

  @override
  Future<ReplicatedEvent?> getPendingEvent(EventId eventId) async =>
      _pendingEvents[eventId];

  @override
  Future<List<ReplicatedEvent>> getPendingEvents(CommandId commandId) async {
    final events =
        _pendingEvents.values
            .where((event) => event.eventId.commandId == commandId)
            .toList()
          ..sort((a, b) => a.eventId.index.compareTo(b.eventId.index));
    return events;
  }

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

  void _validateApplied(AppliedCommand command, List<AppliedEvent> events) {
    final frontier = _appliedVersion();
    if (command.localSequence != _commands.length + 1) {
      throw StateError('out-of-order local command sequence');
    }
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

    var nextEventSequence = _events.length + 1;
    final versions = Map<String, int>.of(_streamVersions);
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.eventId.commandId != command.commandId ||
          event.eventId.index != i ||
          event.localSequence != nextEventSequence++) {
        throw StateError('event identity or local sequence is invalid');
      }
      final nextStreamVersion = (versions[event.streamId] ?? 0) + 1;
      if (event.streamVersion != nextStreamVersion) {
        throw StateError('event stream version is invalid');
      }
      versions[event.streamId] = nextStreamVersion;
    }
  }

  void _appendValidated(AppliedCommand command, List<AppliedEvent> events) {
    _commands.add(command);
    _events.addAll(events);
    for (final event in events) {
      _streamVersions[event.streamId] = event.streamVersion;
    }
  }

  @override
  Future<void> appendApplied(
    AppliedCommand command,
    List<AppliedEvent> events,
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
    _pendingCommands[command.commandId] = command;
  }

  @override
  Future<void> stagePendingEvents(List<ReplicatedEvent> events) async {
    for (final event in events) {
      if (_pendingEvents.containsKey(event.eventId)) {
        throw StateError('event id is already pending');
      }
    }
    for (final event in events) {
      _pendingEvents[event.eventId] = event;
    }
  }

  @override
  Future<void> promotePending(
    AppliedCommand command,
    List<AppliedEvent> events,
  ) async {
    final pending = _pendingCommands[command.commandId];
    if (pending == null ||
        !replicatedCommandsEqual(pending, command.toReplicatedCommand())) {
      throw StateError('matching pending command does not exist');
    }
    _validateApplied(command, events);
    _appendValidated(command, events);
    _pendingCommands.remove(command.commandId);
    for (final event in events) {
      _pendingEvents.remove(event.eventId);
    }
    _onChange?.call();
  }

  @override
  Future<void> reset() async {
    _commands.clear();
    _events.clear();
    _pendingCommands.clear();
    _pendingEvents.clear();
    _streamVersions.clear();
  }
}
