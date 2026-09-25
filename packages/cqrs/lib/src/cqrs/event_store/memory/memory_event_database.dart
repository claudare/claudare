import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/command/command_bundle.dart';
import 'package:cqrs/src/cqrs/event/encoded_event.dart';
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
  }

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
  Future<bool> saveBundle(CommandBundle bundle) async {
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
