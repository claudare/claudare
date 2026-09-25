import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
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
  final EventStore _eventStore;

  factory CqrsTestRuntime({
    EventStore? eventStore,
    Logger? logger,
    TimeProvider? timeProvider,
  }) => CqrsTestRuntime._(
    eventStore ?? EventStore(MemoryEventDatabase()),
    logger ?? const NoopLogger(),
    timeProvider ?? FakeTimeProviderStatic.zero(),
  );

  CqrsTestRuntime._(
    EventStore eventStore,
    Logger logger,
    TimeProvider timeProvider,
  ) : _eventStore = eventStore,
      super(eventStore: eventStore, logger: logger, timeProvider: timeProvider);

  /// Saves [events] in order using codecs in [eventRegistry].
  Future<CqrsTestRuntime> seedEvents(List<TestEvent> events) async {
    final appends = [
      for (final event in events)
        EventAppend(
          streamPath: event.streamPath,
          encodedEvent: eventRegistry.encode(event.event),
          occuredAt: event.occuredAt,
        ),
    ];

    for (final event in appends) {
      final info = await _eventStore.getStreamInfo(event.streamPath);
      await _eventStore.saveChanges(
        CommandChanges(
          dependency: VersionVector(),
          startedAt: event.occuredAt,
          completedAt: event.occuredAt,
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
    return this;
  }
}
