import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';

/// Applies supplied events to an [Aggregate] in order.
/// This provides no testing to load functinonality.
/// FIXME: call .load!
class ProjectionTester<TEvent extends Object> {
  final Projection<TEvent> projection;
  final List<TestEvent<TEvent>> _testEvents = [];
  int _nextEventIndex = 0;

  ProjectionTester(this.projection);

  ProjectionTester<TEvent> withEvent(
    String streamPath,
    TEvent event, {
    String actor = 'a',
    required DateTime occuredAt,
  }) {
    _testEvents.add(
      TestEvent(
        actor: actor,
        stream: streamPath,
        event: event,
        occuredAt: occuredAt,
      ),
    );
    return this;
  }

  Future<void> run() async {
    for (var i = _nextEventIndex; i < _testEvents.length; i++) {
      final event = _testEvents[i];
      if (!projection.filter.doesMatchPath(event.stream)) {
        _nextEventIndex = i + 1;
        continue;
      }

      final envelope = EventEnvelope<TEvent>(
        actor: event.actor,
        streamPath: event.stream,
        event: event.event,
        occuredAt: event.occuredAt,
        logPosition: i,
      );

      await projection.apply(envelope);
      _nextEventIndex = i + 1;
    }
  }
}
