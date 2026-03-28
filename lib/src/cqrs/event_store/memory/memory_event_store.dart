import 'package:core/src/cqrs/causal_sequence.dart';
import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/device_id_sequence_pair.dart';
import 'package:core/src/cqrs/device_sequences.dart';
import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';
import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:core/src/cqrs/time_provider/time_provider.dart';
import 'package:mutex/mutex.dart' show Mutex;

class MemoryEvent {
  final String streamId;
  final String kind;
  final String detail;
  final DateTime createdAt;

  final DeviceId deviceId;
  final int deviceSequence;
  final int causalSequence;
  final int localSequence;
  final int localVersion;

  const MemoryEvent({
    required this.streamId,
    required this.kind,
    required this.detail,
    required this.createdAt,

    required this.deviceId,
    required this.deviceSequence,
    required this.causalSequence,
    required this.localSequence,
    required this.localVersion,
  });

  StoredEventCommandRead get asStoredEventCommandRead => StoredEventCommandRead(
    deviceId: deviceId,
    causalSequence: causalSequence,
    localVersion: localVersion,

    encodedEvent: EncodedEvent(kind: kind, detail: detail),
    occuredAt: createdAt,
  );

  StoredEventProjectionRead get asStoredEventProjectionRead =>
      StoredEventProjectionRead(
        streamId: streamId,
        encodedEvent: EncodedEvent(kind: kind, detail: detail),
        occuredAt: createdAt,
        localSequence: localSequence,
      );

  @override
  String toString() =>
      "MemoryEvent(streamId: $streamId, kind: $kind, detail: $detail, createdAt: $createdAt, deviceId: $deviceId, deviceSequence: $deviceSequence, causalSequence: $causalSequence, localSequence: $localSequence, localVersion: $localVersion)";
}

class MemoryEventInsert {
  final DeviceId deviceId;
  final String streamId;
  final String kind;
  final String detail;
  final int? localVersion;
  final DateTime? emitedAt;

  const MemoryEventInsert({
    required this.deviceId,
    required this.streamId,
    required this.kind,
    required this.detail,
    this.localVersion,
    this.emitedAt,
  });

  MemoryEventInsert.minimal({
    required this.deviceId,
    required this.streamId,
    this.kind = "test",
    this.detail = "{}",
    this.localVersion,
    this.emitedAt,
  });
}

class MemoryCommand {
  final String kind;
  final String detail;
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
  final List<MemoryEvent> _events = [];
  final List<MemoryCommand> _commands = [];
  final CausalSequence _causalSequence = CausalSequence();
  final DeviceSequences _commandDeviceSequences = DeviceSequences();
  final DeviceSequences _eventDeviceSequences = DeviceSequences();
  final Mutex writeTransaction = Mutex(); // TO emulate SQLITE transactions

  final TimeProvider _timeProvider;
  final void Function()? _onChange;

  MemoryEventStore({
    required TimeProvider timeProvider,
    void Function()? onChange,
  }) : _timeProvider = timeProvider,
       _onChange = onChange;

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
        value.localVersion ?? _getStreamEvents(value.streamId).length + 1;

    final event = MemoryEvent(
      deviceId: value.deviceId,
      deviceSequence: nextDeviceSequence,
      causalSequence: nextCausalSequence,
      localSequence: nextLocalSequence,
      localVersion: version,
      streamId: value.streamId,
      kind: value.kind,
      detail: value.detail,
      createdAt: value.emitedAt ?? _timeProvider.now(),
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
            .skipWhile((e) => e.localVersion <= versionCursor)
            .take(count)
            .map((e) => e.asStoredEventCommandRead)
            .toList();

    return Future.value(
      GetStreamEventsResult(originatingVersion: all.length, events: paginated),
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
      originatingVersion: events.length,
    );
  }

  @override
  Future<StreamAppendResult> multiAppendEvents(
    StoredCommandWrite command,
    StreamAppends appends,
  ) async {
    return await writeTransaction.protect(() async {
      final memoryCommand = MemoryCommandInsert(
        deviceId: command.deviceId,
        kind: command.encoded.kind,
        detail: command.encoded.detail,
        startedAt: command.startedAt,
        completedAt: command.completedAt,
        dependencies: appends.dependencies,
        nackReason: command.result.nackReason,
        exception: command.result.exception,
      );

      if (appends.events.isEmpty) {
        return StreamAppendResult.empty();
      }

      final result = StreamAppendResult(orders: []);

      // aggreageteIdStr + latest version (for consistency check)
      final streams = <String, int>{};

      // check local consistency
      for (final lock in appends.localLocks) {
        final info = await getStreamInfo(lock.streamId);

        final originatingVersion = info == null ? 0 : info.originatingVersion;

        streams[lock.streamId] = originatingVersion;

        if (originatingVersion != lock.originatingVersion) {
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
            detail: event.encodedEvent.detail,
            localVersion: version,
            emitedAt: event.occuredAt,
          ),
        );

        result.orders.add(
          StreamAppendOrder(
            localSequence: ins.localSequence,
            localVersion: version,
          ),
        );

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
  Future<GetGlobalEventsResult> getGlobalEvents(
    int sequenceNumber,
    List<PatternFilter> aggregateFilters,
    int count,
  ) async {
    final paginated =
        _events
            .skipWhile((e) => e.localSequence <= sequenceNumber)
            .where(
              (e) => aggregateFilters.any((f) => f.doesMatchPath(e.streamId)),
            )
            .take(count)
            .map((e) => e.asStoredEventProjectionRead)
            .toList();

    return GetGlobalEventsResult(events: paginated, sequenceNumberCursor: null);
  }
}
