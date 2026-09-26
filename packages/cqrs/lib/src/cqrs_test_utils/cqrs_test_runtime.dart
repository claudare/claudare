import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';
import 'package:time_provider/time_provider.dart';

/// Test runtime with event seeding support.
///
/// By default uses a memory event store, noop logger, and static time provider
/// with 0 timestamps.
final class CqrsTestRuntime extends CqrsRuntime {
  static const _testActor = 'test-actor';

  final EventStore _eventStore;

  factory CqrsTestRuntime({
    EventStore? eventStore,
    Logger? logger,
    TimeProvider? timeProvider,
  }) => CqrsTestRuntime._(
    eventStore ?? MemoryEventStore(),
    logger ?? const NoopLogger(),
    timeProvider ?? FakeTimeProviderStatic.zero(),
  );

  CqrsTestRuntime._(
    EventStore eventStore,
    Logger logger,
    TimeProvider timeProvider,
  ) : _eventStore = eventStore,
      super(
        actor: _testActor,
        eventStore: eventStore,
        logger: logger,
        timeProvider: timeProvider,
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
      final info = await _eventStore.getStreamVersion(append.streamPath);
      await _eventStore.saveChanges(
        CommandChanges(
          actor: events[index].actor,
          dependency: CommandDependency(),
          occuredAt: append.occuredAt,
          locks: [
            StreamLock(
              streamPath: append.streamPath,
              originatingStreamVersion: info,
            ),
          ],
          events: [append],
        ),
      );
    }
    return this;
  }
}
