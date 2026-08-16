import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:id_generator/id_generator.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:time_provider/time_provider.dart';

// Max integer value. This is a hacky solution.
// https://stackoverflow.com/a/75928881
// It may have issues, and could silently fail.
const int _maxIntValue = -1 >>> 1;

class CommandTester {
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final EventStore _eventStore;
  final List<EventAppend> _seedEvents = [];
  final EventRegistry _eventRegistry = EventRegistry();

  int? _preRunLastLocalSequence;

  CommandTester({
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
    EventStore? eventStore,
  }) : _timeProvider = timeProvider,
       _idGenerator = idGenerator,
       _eventStore =
           eventStore ??
           EventStore(MemoryEventDatabase(), eventFetchPageSize: _maxIntValue);

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

  CommandTester registerEvent<Event extends Object>(EventCodec<Event> codec) {
    _ensureNotRan();
    _eventRegistry.register(codec);
    return this;
  }

  /// Appends event to the stream with type safety for stream and event.
  CommandTester withEvent<Event extends Object, Params>(
    StreamRoute<Params> streamRoute,
    Params streamParams,
    Event event,
  ) {
    _ensureNotRan();

    final encoded = _eventRegistry.encode(event);

    final streamPath = streamRoute.buildPath(streamParams);
    _seedEvents.add(
      EventAppend(
        streamPath: streamPath,
        encodedEvent: encoded,
        occuredAt: _timeProvider.now(),
      ),
    );

    return this;
  }

  /// Appends event to the stream with type safety for event only.
  CommandTester withEvent2<Event extends Object>(
    String streamPath,
    Event event,
  ) {
    _ensureNotRan();

    final encoded = _eventRegistry.encode(event);

    _seedEvents.add(
      EventAppend(
        streamPath: streamPath,
        encodedEvent: encoded,
        occuredAt: _timeProvider.now(),
      ),
    );

    return this;
  }

  Future<List<Event>> getWrittenEvents<Event extends Object, Params>(
    StreamRoute<Params> streamRoute,
    Params streamParams,
  ) async {
    return getWrittenEvents2<Event>(streamRoute.buildPath(streamParams));
  }

  Future<List<Event>> getWrittenEvents2<Event extends Object>(
    String streamPath,
  ) async {
    _ensureRan();

    // only gets events that were emitted after the test has ran
    final reader = _eventStore.getGlobalReader(
      PatternFilter.exact(streamPath),
      _preRunLastLocalSequence!,
    );

    return reader
        .scan()
        .map((e) => _eventRegistry.decode<Event>(e.encodedEvent))
        .toList();
  }

  Future<void> run<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) async {
    _ensureNotRan();

    await _flushSeeds();

    final res = await _eventStore.getLocalLastEvent(PatternFilter.any());
    _preRunLastLocalSequence = res.localSequence;

    final executer = CommandExecutor(
      eventStore: _eventStore,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
      eventRegistry: _eventRegistry,
    );

    await executer.executeThrowable(command, input);
  }

  // TODO: this can be cleaned up
  Future<void> _flushSeeds() async {
    for (final event in _seedEvents) {
      final info = await _eventStore.getStreamInfo(event.streamPath);
      final timestamp = _timeProvider.now();
      await _eventStore.saveChanges(
        CommandChanges(
          encoded: EncodedCommand(
            kind: 'command-tester-seed',
            bytes: Uint8List(0),
          ),
          startedAt: timestamp,
          completedAt: timestamp,
          locks: [
            StreamLocalLock(
              streamPath: event.streamPath,
              originatingStreamVersion: info?.originatingStreamVersion ?? 0,
            ),
          ],
          events: [event],
        ),
      );
    }
    _seedEvents.clear();
  }
}
