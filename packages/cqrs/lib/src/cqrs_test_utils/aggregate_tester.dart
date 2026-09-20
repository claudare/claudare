import 'package:cqrs/cqrs.dart';

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
//       localSequence: i,
//       streamVersion: i,
//     );
//
//     aggregate.apply(state, envelope);
//   }
//   return state;
// }

/// Replays supplied events against a fresh [Aggregate] state.
class AggregateTester<TEvent extends Object, TParams, TState> {
  final Aggregate<TEvent, TParams, TState> aggregate;
  final List<_TestEvent<TEvent>> _testEvents = [];

  AggregateTester(this.aggregate);

  AggregateTester<TEvent, TParams, TState> withEvent(
    String streamPath,
    TEvent event, {
    required DateTime occuredAt,
  }) {
    _testEvents.add(_TestEvent(streamPath, event, occuredAt));
    return this;
  }

  TState run() {
    final state = aggregate.initialState();
    for (var i = 0; i < _testEvents.length; i++) {
      final event = _testEvents[i];
      if (!aggregate.streamRoute.matches(event.streamPath)) continue;

      final envelope = EventEnvelope<TEvent, TParams>(
        streamPath: event.streamPath,
        streamParams: aggregate.streamRoute.parseParams(event.streamPath),
        event: event.event,
        occuredAt: event.occuredAt,
        localSequence: i,
        streamVersion: i,
      );
      if (aggregate.canApply(envelope)) aggregate.apply(state, envelope);
    }
    return state;
  }
}

final class _TestEvent<TEvent extends Object> {
  final String streamPath;
  final TEvent event;
  final DateTime occuredAt;

  const _TestEvent(this.streamPath, this.event, this.occuredAt);
}
