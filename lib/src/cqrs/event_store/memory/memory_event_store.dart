import 'dart:typed_data' show Uint8List;

import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/event/stored_event_command_read.dart';
import 'package:core/src/cqrs/event/stored_event_projection_read.dart';
import 'package:core/utils.dart';
import 'package:mutex/mutex.dart' show Mutex;

import 'package:core/src/cqrs/causal_sequence.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/device_sequences.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

/// Reference memory implementation.
class MemoryEventStore implements EventStore {
  final List<MemoryEvent> _events = [];
  final List<MemoryCommand> _commands = [];
  final CausalSequence _causalSequence = CausalSequence();
  final DeviceSequences _commandDeviceSequences = DeviceSequences();
  final DeviceSequences _eventDeviceSequences = DeviceSequences();
  final Mutex writeTransaction = Mutex(); // TO emulate SQLITE transactions

  final void Function()? _onChange;

  MemoryEventStore({void Function()? onChange}) : _onChange = onChange;

  void _emitChange() {
    _onChange?.call();
  }

  // testing specigfic functions... dont rely on them

  MemoryEvent testInsertEvent(MemoryEventInsert value) {
    final event = _insertEvent(value);

    _emitChange();
    return event;
  }

  Iterable<MemoryEvent> testGetStreamEvents(String streamIdStr) {
    return _getStreamEvents(streamIdStr);
  }

  List<MemoryEvent> get testAllEvents => _events;
  List<MemoryCommand> get testAllCommands => _commands;

  Iterable<MemoryEvent> _getStreamEvents(String streamIdStr) {
    return _events.where((e) => e.streamId == streamIdStr);
  }

  MemoryEvent _insertEvent(MemoryEventInsert value) {
    final nextLocalSequence = _events.length + 1; // no zeros!

    final nextDeviceSequence = _eventDeviceSequences.nextSequence(
      value.deviceId,
    );
    final nextCausalSequence = _causalSequence.nextSequence(value.deviceId);
    final version =
        value.streamVersion ?? _getStreamEvents(value.streamId).length + 1;

    final event = MemoryEvent(
      deviceId: value.deviceId,
      deviceSequence: nextDeviceSequence,
      causalSequence: nextCausalSequence,
      localSequence: nextLocalSequence,
      streamId: value.streamId,
      streamVersion: version,
      kind: value.kind,
      detail: value.detail,
      createdAt: value.occuredAt,
    );

    _events.add(event);

    return event;
  }

  MemoryCommand _insertCommand(MemoryCommandInsert value) {
    final nextLocalSequence = _commands.length + 1; // no zeros!

    final nextDeviceSequence = _commandDeviceSequences.nextSequence(
      value.deviceId,
    );

    final command = MemoryCommand(
      deviceId: value.deviceId,
      deviceSequence: nextDeviceSequence,
      localSequence: nextLocalSequence,
      kind: value.kind,
      detail: value.detail,
      startedAt: value.startedAt,
      completedAt: value.completedAt,
      dependencies: value.dependencies,
      exception: null,
      nackReason: null,
    );

    _commands.add(command);

    return command;
  }

  // --- command

  @override
  Future<GetStreamEventsResult> getStreamEvents(
    String streamIdStr,
    int count,
    int versionCursor,
  ) {
    final all = _getStreamEvents(streamIdStr);

    // we need to get the correct version cursor
    final paginated =
        all
            .skipWhile((e) => e.streamVersion <= versionCursor)
            .take(count)
            .map((e) => e.asStoredEventCommandRead)
            .toList();

    return Future.value(
      GetStreamEventsResult(
        originatingStreamVersion: all.length,
        events: paginated,
      ),
    );
  }

  @override
  Future<GetStreamInfoResult?> getStreamInfo(String streamId) async {
    final events = _getStreamEvents(streamId);

    if (events.isEmpty) {
      return null;
    }

    return GetStreamInfoResult(
      causalSequencePair: DeviceIdSequencePair(
        events.last.deviceId,
        events.last.causalSequence,
      ),
      originatingStreamVersion: events.length,
    );
  }

  @override
  Future<SaveChangesResult> saveChanges(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    return await writeTransaction.protect(() async {
      final memoryCommand = MemoryCommandInsert(
        deviceId: command.deviceId,
        kind: command.encoded.kind,
        detail: command.encoded.bytes,
        startedAt: command.startedAt,
        completedAt: command.completedAt,
        dependencies: appends.dependencies,
        nackReason: command.result.nackReason,
        exception: command.result.exception,
      );

      if (appends.events.isEmpty) {
        return SaveChangesResult.empty();
      }

      final result = SaveChangesResult(orders: []);

      // aggreageteIdStr + latest version (for consistency check)
      final streams = <String, int>{};

      // check local consistency
      for (final lock in appends.localLocks) {
        final info = await getStreamInfo(lock.streamId);

        final originatingStreamVersion =
            info == null ? 0 : info.originatingStreamVersion;

        streams[lock.streamId] = originatingStreamVersion;

        if (originatingStreamVersion != lock.originatingStreamVersion) {
          throw ConcurrencyProblem();
        }
      }

      // insert the events
      for (final event in appends.events) {
        final streamIdStr = event.streamId;
        final prevVersion = streams[streamIdStr];

        assert(prevVersion != null);

        final version = prevVersion! + 1;

        final ins = _insertEvent(
          MemoryEventInsert(
            deviceId: command.deviceId,
            streamId: streamIdStr,
            kind: event.encodedEvent.kind,
            detail: event.encodedEvent.bytes,
            streamVersion: version,
            occuredAt: event.occuredAt,
          ),
        );

        result.orders.add(StreamAppendOrder(localSequence: ins.localSequence));

        streams[streamIdStr] = version;
      }

      _insertCommand(memoryCommand);

      _emitChange();

      assert(result.orders.length == appends.events.length);

      return result;
    });
  }

  // --- projection

  @override
  Future<GetLocalEventsResult> getLocalEvents(
    PatternFilter patternFilter,
    int sequenceNumber,
    int count,
  ) async {
    final paginated =
        _events
            .skipWhile((e) => e.localSequence <= sequenceNumber)
            .where((e) => patternFilter.doesMatchPath(e.streamId))
            .take(count)
            .map((e) => e.asStoredEventProjectionRead)
            .toList();

    return GetLocalEventsResult(events: paginated, sequenceNumberCursor: null);
  }

  @override
  Future<GetLocalLastEventResult> getLocalLastEvent(
    PatternFilter patternFilter,
  ) async {
    final last =
        _events
            .where((e) => patternFilter.doesMatchPath(e.streamId))
            .lastOrNull;

    final localSequence = last?.localSequence ?? 0;

    return GetLocalLastEventResult(localSequence: localSequence);
  }
}

class MemoryEvent {
  final String streamId;
  final String kind;
  final Uint8List detail;
  final DateTime createdAt;

  final DeviceId deviceId;
  final int deviceSequence;
  final int causalSequence;
  final int localSequence;
  final int streamVersion;

  const MemoryEvent({
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.createdAt,

    required this.deviceId,
    required this.deviceSequence,
    required this.causalSequence,
    required this.localSequence,
    required this.streamVersion,
  });

  StoredEventCommandRead get asStoredEventCommandRead => StoredEventCommandRead(
    causalPair: DeviceIdSequencePair(deviceId, causalSequence),
    streamVersion: streamVersion,

    encodedEvent: EncodedEvent(kind: kind, bytes: detail),
    occuredAt: createdAt,
  );

  StoredEventProjectionRead get asStoredEventProjectionRead =>
      StoredEventProjectionRead(
        streamId: streamId,
        encodedEvent: EncodedEvent(kind: kind, bytes: detail),
        occuredAt: createdAt,
        localSequence: localSequence,
      );

  @override
  String toString() =>
      "MemoryEvent(streamId: $streamId, kind: $kind, detail: $detail, createdAt: $createdAt, deviceId: $deviceId, deviceSequence: $deviceSequence, causalSequence: $causalSequence, localSequence: $localSequence, localVersion: $streamVersion)";
}

class MemoryEventInsert {
  final DeviceId deviceId;
  final String streamId;
  final String kind;
  final Uint8List detail;
  final DateTime occuredAt;
  final int? streamVersion;

  const MemoryEventInsert({
    required this.deviceId,
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.occuredAt,
    this.streamVersion,
  });

  MemoryEventInsert.minimal({
    required this.deviceId,
    required this.streamId,
    required this.occuredAt,
    this.kind = "test",
    this.streamVersion,
    Uint8List? detail,
  }) : detail = detail ?? JsonConverter.encode({});
}

class MemoryCommand {
  final String kind;
  final Uint8List detail;
  final DateTime startedAt;
  final DateTime completedAt;

  final EventDependency dependencies;
  final DeviceId deviceId;
  final int deviceSequence;
  final int localSequence;

  final String? nackReason;
  final Exception? exception;

  const MemoryCommand({
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,

    required this.dependencies,
    required this.deviceId,
    required this.deviceSequence,
    required this.localSequence,

    required this.nackReason,
    required this.exception,
  });

  @override
  String toString() =>
      "MemoryCommand(kind: $kind, detail: $detail, startedAt: $startedAt, completedAt: $completedAt, dependencies: $dependencies, deviceId: $deviceId, deviceSequence: $deviceSequence, localSequence: $localSequence, nackReason: $nackReason, exception: $exception)";
}

class MemoryCommandInsert {
  final DeviceId deviceId;

  final String kind;
  final Uint8List detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  final String? nackReason;
  final Exception? exception;

  const MemoryCommandInsert({
    required this.deviceId,
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,
    required this.nackReason,
    required this.exception,
  });
}
