import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:cqrs/src/cqrs/snapshot.dart';

/// Applies events to mutable aggregate state.
abstract interface class AggregateState<TEvent extends Object> {
  /// Mutates this state for [envelope].
  void apply(EventEnvelope<TEvent> envelope);

  /// Handles permanent deletion of a matching stream.
  void onStreamDeleted(StreamDeletion deletion);
}

/// Metadata for a permanent stream deletion.
class StreamDeletion {
  final String actor;
  final String streamPath;
  final DateTime occuredAt;

  const StreamDeletion({
    required this.actor,
    required this.streamPath,
    required this.occuredAt,
  });
}

typedef ApplyEnvelope<TEvent extends Object> = void Function(
  EventEnvelope<TEvent> envelope,
);

/// Defines event selection, mutable state, and sequence tracking for aggregate
/// resolution.
class Aggregate<TEvent extends Object, TState extends AggregateState<TEvent>> {
  /// Name used in diagnostics.
  final String name;
  final LogFilter filter;
  final TState state;
  int? sequence;

  Aggregate({
    required this.name,
    required this.filter,
    required this.state,
    this.sequence,
  });

  Snapshot<TState> snapshot() => Snapshot(state, sequence);

  @override
  String toString() => name;
}
