import 'package:core/src/cqrs/causal_sequence.dart';
import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/device_sequences.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/pattern_filter.dart';

class _MemoryEvent {
  final DeviceId deviceId;
  final int deviceSequence;
  final int causalSequence;
  final int localSequence;
  final int version;

  final String streamId;
  final String kind;
  final String detail;
  final String metadata;
  final DateTime createdAt;

  const _MemoryEvent({
    required this.deviceId,
    required this.deviceSequence,
    required this.causalSequence,
    required this.localSequence,
    required this.version,
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.metadata,
    required this.createdAt,
  });

  StoredEventCommandRead get asStoredEventCommandRead => StoredEventCommandRead(
    deviceId: deviceId,
    causalSequence: causalSequence,

    kind: kind,
    detail: detail,
    metadata: metadata,
    createdAt: createdAt,
  );

  StoredEventProjectionRead get asStoredEventProjectionRead =>
      StoredEventProjectionRead(
        streamId: streamId,
        kind: kind,
        detail: detail,
        metadata: metadata,
        createdAt: createdAt,
        localSequence: localSequence,
      );
}

class MemoryEventInsert {
  final DeviceId deviceId;
  final String streamId;
  final String kind;
  final String detail;
  final String metadata;
  final int? version;
  final DateTime? createdAt;

  const MemoryEventInsert({
    required this.deviceId,
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.metadata,
    this.version,
    this.createdAt,
  });
}

class _MemoryCommand {
  final DeviceId deviceId;
  final int deviceSequence;
  final int localSequence;

  final String kind;
  final String detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  final String? nackReason;
  final Exception? exception;

  const _MemoryCommand({
    required this.deviceId,
    required this.deviceSequence,
    required this.localSequence,
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,
    required this.nackReason,
    required this.exception,
  });
}

class MemoryCommandInsert {
  final DeviceId deviceId;

  final String kind;
  final String detail;
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

class MemoryEventStore implements EventStore {
  final List<_MemoryEvent> _events = [];
  final List<_MemoryCommand> _commands = [];
  final CausalSequence _causalSequence = CausalSequence();
  final DeviceSequences _commandDeviceSequences = DeviceSequences();
  final DeviceSequences _eventDeviceSequences = DeviceSequences();

  final DateTime Function() _getTime;
  final void Function()? _onChange;

  MemoryEventStore({
    required DateTime Function() getTime,
    void Function()? onChange,
  }) : _onChange = onChange,
       _getTime = getTime;

  void _emitChange() {
    _onChange?.call();
  }

  List<_MemoryEvent> _getStreamEvents(String streamIdStr) {
    return _events.where((e) => e.streamId == streamIdStr).toList();
  }

  _MemoryEvent _insertEvent(MemoryEventInsert value) {
    final nextLocalSequence = _events.length + 1; // no zeros!

    final nextDeviceSequence = _eventDeviceSequences.nextSequence(
      value.deviceId,
    );
    final nextCausalSequence = _causalSequence.nextSequence(value.deviceId);
    final version =
        value.version ?? _getStreamEvents(value.streamId).length + 1;

    final event = _MemoryEvent(
      deviceId: value.deviceId,
      deviceSequence: nextDeviceSequence,
      causalSequence: nextCausalSequence,
      localSequence: nextLocalSequence,
      version: version,
      streamId: value.streamId,
      kind: value.kind,
      detail: value.detail,
      metadata: value.metadata,
      createdAt: value.createdAt ?? _getTime(),
    );

    _events.add(event);

    return event;
  }

  _MemoryCommand _insertCommand(MemoryCommandInsert value) {
    final nextLocalSequence = _commands.length + 1; // no zeros!

    final nextDeviceSequence = _commandDeviceSequences.nextSequence(
      value.deviceId,
    );

    final command = _MemoryCommand(
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
  Future<GetStreamEventsResult> getStreamEventsCursor(
    String streamIdStr,
    int count,
    int? versionCursor,
  ) {
    final events = _getStreamEvents(streamIdStr);

    // TODO: paginate

    return Future.value(
      GetStreamEventsResult(
        originatingVersion: events.length,
        versionCursor: null,
        events: events.map((e) => e.asStoredEventCommandRead).toList(),
      ),
    );
  }

  @override
  Future<GetStreamInfoResult> getStreamInfo(String streamId) {
    final events = _getStreamEvents(streamId);
    final count = events.length;
    final firstCausalSequencePair =
        events.isNotEmpty
            ? DeviceIdSequencePair(
              events.first.deviceId,
              events.first.causalSequence,
            )
            : null;
    final lastCausalSequencePair =
        events.isNotEmpty
            ? DeviceIdSequencePair(
              events.last.deviceId,
              events.last.causalSequence,
            )
            : null;

    return Future.value(
      GetStreamInfoResult(
        totalEventCount: count,
        firstCausalSequencePair: firstCausalSequencePair,
        lastCausalSequencePair: lastCausalSequencePair,
      ),
    );
  }

  @override
  Future<StreamAppendResult> multiAppendEvents(
    DeviceId thisDeviceId,
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    final memoryCommand = MemoryCommandInsert(
      deviceId: thisDeviceId,
      kind: command.kind,
      detail: command.detail,
      startedAt: command.startedAt,
      completedAt: command.completedAt,
      dependencies: command.dependencies,
      exception: null,
      nackReason: null,
    );

    final result = StreamAppendResult(orders: []);

    // aggreageteIdStr + latest version (for consistency check)
    final streams = <String, int>{};

    // check consistency
    for (final lock in appends.locks) {
      final info = await getStreamInfo(lock.streamIdStr);

      final originatingVersion = info.totalEventCount;

      streams[lock.streamIdStr] = originatingVersion;

      if (originatingVersion != lock.originatingVersion) {
        throw ConcurrencyProblem();
      }
    }

    // insert the events
    for (final event in appends.events) {
      final streamIdStr = event.streamId;
      final prevVersion = streams[streamIdStr];
      if (prevVersion == null) {
        throw StateError('Incorrect command implementation (internal)');
      }
      final version = prevVersion + 1;

      final ins = _insertEvent(
        MemoryEventInsert(
          deviceId: thisDeviceId,
          streamId: streamIdStr,
          kind: event.kind,
          detail: event.detail,
          metadata: event.metadata,
          version: version,
          createdAt: event.createdAt,
        ),
      );

      result.orders.add(
        StreamAppendOrder(localSequence: ins.localSequence, version: version),
      );

      streams[streamIdStr] = version;
    }

    _insertCommand(memoryCommand);

    _emitChange();

    assert(result.orders.length == appends.events.length);

    return result;
  }

  // --- projection

  @override
  Future<GetGlobalEventsResult> getGlobalEvents(
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  ) async {
    // TODO: pagination
    final answer =
        _events
            .sublist(sequenceNumber)
            .where(
              (e) => aggregateFilters.any((f) => f.doesMatchPath(e.streamId)),
            )
            .map((e) => e.asStoredEventProjectionRead)
            .toList();

    return GetGlobalEventsResult(events: answer, sequenceNumberCursor: null);
  }
}
