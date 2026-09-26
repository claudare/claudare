import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';

/// Applies supplied events to an [Aggregate] in order.
class AggregateTester<
  TEvent extends Object,
  TState extends AggregateState<TEvent>
> {
  final Aggregate<TEvent, TState> aggregate;
  final List<TestEvent<TEvent>> _testEvents = [];
  int _nextEventIndex = 0;

  AggregateTester(this.aggregate);

  AggregateTester<TEvent, TState> withEvent(
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

  TState run() {
    for (var i = _nextEventIndex; i < _testEvents.length; i++) {
      final event = _testEvents[i];
      if (!aggregate.filter.doesMatchPath(event.stream)) {
        _nextEventIndex = i + 1;
        continue;
      }

      final envelope = EventEnvelope<TEvent>(
        actor: event.actor,
        streamPath: event.stream,
        event: event.event,
        occuredAt: event.occuredAt,
      );
      aggregate.state.apply(envelope);
      aggregate.sequence = i;
      _nextEventIndex = i + 1;
    }
    return aggregate.state;
  }
}
