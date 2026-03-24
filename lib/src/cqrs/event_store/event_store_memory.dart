import 'package:core/src/cqrs/causal_sequence.dart';
import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/device_sequences.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
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
}

class _MemoryEventInsert {
  final DeviceId deviceId;
  final String streamId;
  final String kind;
  final String detail;
  final String metadata;
  final int? version;
  final DateTime? createdAt;

  const _MemoryEventInsert({
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
    this.nackReason,
    this.exception,
  });
}

class EventStoreMemory implements EventStoreCommand, EventStoreProjection {
  final List<_MemoryEvent> events = [];
  final List<_MemoryCommand> commands = [];

  final CausalSequence causalSequence = CausalSequence();
  final DeviceSequences commandDeviceSequences = DeviceSequences();
  final DeviceSequences eventDeviceSequences = DeviceSequences();

  final DateTime Function() getTime;
  final void Function()? onChange;

  EventStoreMemory({required this.getTime, this.onChange});

  void _emitChange() {
    onChange?.call();
  }

  List<_MemoryEvent> _getSteamEvents(String streamIdStr) {
    return events.where((e) => e.streamId == streamIdStr).toList();
  }

  int _getStreamEventsCount(String streamIdStr) {
    return events.where((e) => e.streamId == streamIdStr).length;
  }

  _MemoryEvent _insertEvent(_MemoryEventInsert value) {
    final nextLocalSequence = events.length + 1; // no zeros!

    final nextDeviceSequence = eventDeviceSequences.nextSequence(
      value.deviceId,
    );
    final nextCausalSequence = causalSequence.nextSequence(value.deviceId);
    final version = value.version ?? _getStreamEventsCount(value.streamId) + 1;

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
      createdAt: value.createdAt ?? getTime(),
    );

    events.add(event);

    return event;
  }

  // --- command

  @override
  Future<GetStreamEventsResult> getStreamEventsCursor(
    String streamIdStr,
    int count,
    int? versionCursor,
  ) {
    final events = _getSteamEvents(streamIdStr);

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
  Future<GetStreamMinimalResult> getStreamMinimal(String streamId) {
    final count = _getStreamEventsCount(streamId);

    return Future.value(
      GetStreamMinimalResult(totalCount: count, originatingVersion: count),
    );
  }

  @override
  Future<StreamAppendResult> multiAppendEvents(
    DeviceId thisDeviceId,
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    final memoryCommand = _MemoryCommand(
      deviceId: thisDeviceId, // TODO: get rid of me
      deviceSequence: commandDeviceSequences.nextSequence(thisDeviceId),
      localSequence: commands.length + 1,
      kind: command.kind,
      detail: command.detail,
      startedAt: command.startedAt,
      completedAt: command.completedAt,
      dependencies: command.dependencies,
    );

    final result = StreamAppendResult(orders: []);

    // aggreageteIdStr + latest version (for consistency check)
    final streams = <String, int>{};

    // check consistency
    for (final lock in appends.locks) {
      final info = await getStreamMinimal(lock.streamIdStr);

      streams[lock.streamIdStr] = info.originatingVersion;

      if (info.originatingVersion != lock.originatingVersion) {
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
        _MemoryEventInsert(
          deviceId: thisDeviceId,
          streamId: streamIdStr,
          kind: event.kind,
          detail: event.detail,
          metadata: event.metadata,
          version: version,
          createdAt: getTime(),
        ),
      );

      result.orders.add(
        StreamAppendOrder(localSequence: ins.localSequence, version: version),
      );

      streams[streamIdStr] = version;
    }

    _emitChange();

    return result;
  }

  // --- projection

  @override
  Future<GetGlobalEventsResult> getGlobalEvents(
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  ) {
    // TODO: implement getGlobalEvents
    throw UnimplementedError();
  }
}
