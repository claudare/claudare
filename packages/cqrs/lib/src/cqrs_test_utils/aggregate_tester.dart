import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs_test_utils/test_event.dart';

// prototype: please do not delete
// TState testAggregate<TEvent extends Object, TState>(
//   List<TEvent> withEvents,
//   Aggregate<TEvent, dynamic, TState> aggregate,
// ) {
//   TState state = aggregate.initialState();
//   for (var i = 0; i < withEvents.length; i++) {
//     final event = withEvents[i];
//     final envelope = EventEnvelope(
//       streamPath: 'TODO',
//       streamParams: 'TODO',
//       event: event,
//       occuredAt: DateTime.fromMillisecondsSinceEpoch(i),
//       logPosition: i,
//       streamVersion: i,
//     );
//
//     aggregate.apply(state, envelope);
//   }
//   return state;
// }

/// Replays supplied events against a fresh [Aggregate] state.
class AggregateTester<TEvent extends Object, TState> {
  final Aggregate<TEvent, TState> aggregate;
  final List<TestEvent<TEvent>> _testEvents = [];

  AggregateTester(this.aggregate);

  AggregateTester<TEvent, TState> withEvent(
    String streamPath,
    TEvent event, {
    required DateTime occuredAt,
  }) {
    _testEvents.add(TestEvent(streamPath, event, occuredAt));
    return this;
  }

  TState run() {
    final state = aggregate.initialState();
    for (var i = 0; i < _testEvents.length; i++) {
      final event = _testEvents[i];
      if (!aggregate.streamRoute.matches(event.streamPath)) continue;

      final envelope = EventEnvelope<TEvent>(
        streamPath: event.streamPath,
        event: event.event,
        occuredAt: event.occuredAt,
      );
      if (aggregate.canApply(envelope)) aggregate.apply(state, envelope);
    }
    return state;
  }
}
