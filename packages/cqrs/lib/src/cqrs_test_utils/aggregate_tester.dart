import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';

/// Replays supplied events against a fresh [Aggregate] state.
class AggregateTester<TEvent extends Object, TState> {
  final Aggregate<TEvent, TState> aggregate;
  final List<TestEvent<TEvent>> _testEvents = [];

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
    final state = aggregate.initialState();
    for (var i = 0; i < _testEvents.length; i++) {
      final event = _testEvents[i];
      if (!aggregate.streamRoute.matches(event.stream)) continue;

      final envelope = EventEnvelope<TEvent>(
        actor: event.actor,
        streamPath: event.stream,
        event: event.event,
        occuredAt: event.occuredAt,
      );
      if (aggregate.canApply(envelope)) aggregate.apply(state, envelope);
    }
    return state;
  }
}
