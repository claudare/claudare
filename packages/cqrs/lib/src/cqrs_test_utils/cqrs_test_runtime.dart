import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';
import 'package:time_provider/time_provider.dart';
import 'package:id_generator/id_generator.dart';

/// Test runtime with event seeding support.
///
/// Defaults to memory stores, sequential IDs, and zero timestamps.
final class CqrsTestRuntime extends CqrsRuntime {
  static const _testActor = 'test-actor';

  final EventStore _eventStore;

  factory CqrsTestRuntime({
    EventStore? eventStore,
    TimeProvider? timeProvider,
    IdGenerator? idGenerator,
  }) => CqrsTestRuntime._(
    eventStore ?? MemoryEventStore(),
    timeProvider ?? FakeTimeProviderStatic.zero(),
    idGenerator ?? IdGeneratorSequential(),
  );

  CqrsTestRuntime._(
    EventStore eventStore,
    TimeProvider timeProvider,
    IdGenerator idGenerator,
  ) : _eventStore = eventStore,
      super(
        actor: _testActor,
        eventStore: eventStore,
        timeProvider: timeProvider,
        idGenerator: idGenerator,
      );

  /// Saves [events] in order using codecs in [eventRegistry].
  Future<CqrsTestRuntime> seedEvents(List<TestEvent> events) async {
    final appends = [
      for (final event in events)
        EventAppend(
          streamPath: event.stream,
          encodedEvent: eventRegistry.encode(event.event),
          occuredAt: event.occuredAt,
        ),
    ];

    for (var index = 0; index < appends.length; index++) {
      final append = appends[index];
      final info = await _eventStore.getStreamInfo(append.streamPath);
      await _eventStore.saveChanges(
        CommandChanges(
          actor: events[index].actor,
          dependency: CommandDependency(),
          occuredAt: append.occuredAt,
          locks: [
            StreamLock(
              streamPath: append.streamPath,
              originatingStreamVersion: info.version,
            ),
          ],
          events: [append],
        ),
      );
    }
    return this;
  }
}
