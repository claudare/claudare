import 'package:core/cqrs.dart';
import 'package:core/device_id.dart';
import 'package:core/id_generator.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:core/time_provider.dart';

// Max integer value. This is a hacky solution.
// https://stackoverflow.com/a/75928881
// It may have issues, and could silently fail.
const int _maxIntValue = -1 >>> 1;

// TODO: this currently relies on MemoryEventStore
class CommandTester {
  final DeviceId _deviceId;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final MemoryEventStore _eventStore;

  int? _preRunLastLocalSequence;

  CommandTester({
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
    MemoryEventStore? eventStore,
    DeviceId deviceId = const DeviceId.unassigned(),
  }) : _timeProvider = timeProvider,
       _idGenerator = idGenerator,
       _eventStore = eventStore ?? MemoryEventStore(),
       _deviceId = deviceId;

  void _ensureRan() {
    if (_preRunLastLocalSequence == null) {
      throw StateError('tester did not ran, but it should have been');
    }
  }

  void _ensureNotRan() {
    if (_preRunLastLocalSequence != null) {
      throw StateError('tester already ran, but it should not have been');
    }
  }

  /// Appends event to the stream with type safety for stream and event.
  CommandTester withEvent<Event, IdData>(
    StreamIdPattern<IdData> streamIdPattern,
    IdData streamData,
    EventCodec<Event> eventCodec,
    Event event,
  ) {
    _ensureNotRan();

    final encoded = eventCodec.encode(event);

    final streamPath = streamIdPattern.toPath(streamData);
    _eventStore.testInsertEvent(
      MemoryEventInsert(
        deviceId: _deviceId,
        streamId: streamPath,
        kind: encoded.kind,
        detail: encoded.detail,
        occuredAt: _timeProvider.now(),
      ),
    );

    return this;
  }

  /// Appends event to the stream with type safety for event only.
  CommandTester withEvent2<Event, IdData>(
    String streamIdPath,
    EventCodec<Event> eventCodec,
    Event event,
  ) {
    _ensureNotRan();

    final encoded = eventCodec.encode(event);

    _eventStore.testInsertEvent(
      MemoryEventInsert(
        deviceId: _deviceId,
        streamId: streamIdPath,
        kind: encoded.kind,
        detail: encoded.detail,
        occuredAt: _timeProvider.now(),
      ),
    );

    return this;
  }

  Future<List<Event>> getWrittenEvents<Event, IdData>(
    EventCodec<Event> eventCodec,
    StreamIdPattern<IdData> streamIdPattern,
    IdData streamData,
  ) async {
    return getWrittenEvents2(eventCodec, streamIdPattern.toPath(streamData));
  }

  Future<List<Event>> getWrittenEvents2<Event>(
    EventCodec<Event> eventCodec,
    String streamIdPath,
  ) async {
    _ensureRan();

    // only gets events that were emitted after the test has ran
    final values = await _eventStore.getLocalEvents(
      PatternFilter.exact(streamIdPath),
      _preRunLastLocalSequence!,
      _maxIntValue,
    );

    return values.events
        .map((e) => eventCodec.decode(e.encodedEvent))
        .toList(growable: false);
  }

  /// Returns true on succeess, false on failure.
  /// If failure is encountered, check [nackMessage] and [error].
  Future<CommandRunResult> run<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) async {
    _ensureNotRan();

    final res = await _eventStore.getLocalLastEvent(PatternFilter.any());
    _preRunLastLocalSequence = res.localSequence;

    final executer = CommandExecutor(
      eventStore: _eventStore,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
      thisDeviceId: _deviceId,
      pageSize: _maxIntValue,
    );

    // envelopes are ingored
    return await wrapCommandExecutionFuture(
      executer.executeThrowable(command, input),
    );
  }
}
