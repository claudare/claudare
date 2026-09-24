import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:time_provider/time_provider.dart';

// Max integer value. This is a hacky solution.
// https://stackoverflow.com/a/75928881
// It may have issues, and could silently fail.
const int _maxIntValue = -1 >>> 1;

// TODO: create a proper CqrsRuntime for testing.
class CommandTester {
  final TimeProvider _timeProvider;
  final EventDatabase _eventDatabase;
  final EventStore _eventStore;
  final List<EventAppend> _seedEvents = [];
  final EventRegistry _eventRegistry = EventRegistry();

  int? _preRunLastLogPosition;
  bool _ran = false;

  CommandTester({
    required TimeProvider timeProvider,
    EventDatabase? eventDatabase,
  }) : this._(
         timeProvider: timeProvider,
         eventDatabase: eventDatabase ?? MemoryEventDatabase(),
       );

  CommandTester._({
    required TimeProvider timeProvider,
    required EventDatabase eventDatabase,
  }) : _timeProvider = timeProvider,
       _eventDatabase = eventDatabase,
       _eventStore = EventStore(
         eventDatabase,
         eventFetchPageSize: _maxIntValue,
       );

  void _ensureRan() {
    if (!_ran) {
      throw StateError('tester did not ran, but it should have been');
    }
  }

  void _ensureNotRan() {
    if (_ran) {
      throw StateError('tester already ran, but it should not have been');
    }
  }

  CommandTester registerEvent<Event extends Object>(EventCodec<Event> codec) {
    _ensureNotRan();
    _eventRegistry.add(codec);
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
    final reader = _eventStore.getLogEventReader(
      (_preRunLastLogPosition ?? -1) + 1,
    );

    return reader
        .scan()
        .where((event) => event.streamPath == streamPath)
        .map((e) => _eventRegistry.decode<Event>(e.encodedEvent))
        .toList();
  }

  Future<void> run<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) async {
    _ensureNotRan();

    await _flushSeeds();

    final state = await _eventDatabase.getState();
    _preRunLastLogPosition = state.lastEventLogPosition;
    _ran = true;

    final executer = CommandExecutor(
      eventStore: _eventStore,
      timeProvider: _timeProvider,
      eventRegistry: _eventRegistry,
      logger: const NoopLogger(),
    );

    await executer.execute(command, input);
  }

  // TODO: this can be cleaned up
  Future<void> _flushSeeds() async {
    for (final event in _seedEvents) {
      final info = await _eventStore.getStreamInfo(event.streamPath);
      final timestamp = _timeProvider.now();
      await _eventStore.saveChanges(
        CommandChanges(
          dependency: VersionVector(),
          encoded: EncodedCommand(
            kind: 'command-tester-seed',
            bytes: Uint8List(0),
          ),
          startedAt: timestamp,
          completedAt: timestamp,
          locks: [
            StreamLock(
              streamPath: event.streamPath,
              originatingStreamVersion: info?.originatingStreamVersion,
            ),
          ],
          events: [event],
        ),
      );
    }
    _seedEvents.clear();
  }
}
