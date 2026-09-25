import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:time_provider/time_provider.dart';

/// Executes a command and inspects its emitted events.
class CommandTester {
  final TimeProvider _timeProvider;
  final EventStore _eventStore;
  final List<EventAppend> _seedEvents = [];
  late final CqrsRuntime _runtime;

  EventRegistry get _eventRegistry => _runtime.eventRegistry;

  int? _preRunLastLogPosition;
  bool _ran = false;

  CommandTester({required TimeProvider timeProvider, EventStore? eventStore})
    : _timeProvider = timeProvider,
      _eventStore = eventStore ?? MemoryEventStore() {
    _runtime = CqrsRuntime(
      eventStore: _eventStore,
      timeProvider: timeProvider,
      logger: const NoopLogger(),
    );
  }

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
  CommandTester withEvent<Event extends Object>(
    StreamRoute streamRoute,
    String streamParams,
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

  Future<List<Event>> getWrittenEvents<Event extends Object>(
    StreamRoute streamRoute,
    String streamParams,
  ) async {
    return getWrittenEvents2<Event>(streamRoute.buildPath(streamParams));
  }

  Future<List<Event>> getWrittenEvents2<Event extends Object>(
    String streamPath,
  ) async {
    _ensureRan();

    // only gets events that were emitted after the test has ran
    final reader = _runtime.logReader((_preRunLastLogPosition ?? -1) + 1);

    return reader
        .scan()
        .where((event) => event.streamPath == streamPath)
        .map((e) => _eventRegistry.decode<Event>(e.encodedEvent))
        .toList();
  }

  Future<void> run(Command command) async {
    _ensureNotRan();

    await _flushSeeds();

    final state = await _eventStore.getState();
    _preRunLastLogPosition = state.lastEventLogPosition;
    _ran = true;

    await _runtime.execute(command);
  }

  // TODO: this can be cleaned up
  Future<void> _flushSeeds() async {
    for (final event in _seedEvents) {
      final info = await _eventStore.getStreamVersion(event.streamPath);
      final timestamp = _timeProvider.now();
      await _eventStore.saveChanges(
        CommandChanges(
          dependency: VersionVector(),
          occuredAt: timestamp,
          locks: [
            StreamLock(
              streamPath: event.streamPath,
              originatingStreamVersion: info,
            ),
          ],
          events: [event],
        ),
      );
    }
    _seedEvents.clear();
  }
}
