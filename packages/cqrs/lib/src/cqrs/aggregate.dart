import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:cqrs/src/cqrs/snapshot.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/stream_deletion.dart';

/// Applies events to mutable aggregate state.
abstract interface class AggregateState<TEvent extends Object> {
  /// Mutates this state for [envelope].
  void apply(EventEnvelope<TEvent> envelope);

  /// Handles permanent deletion of a matching stream.
  void onStreamDeleted(StreamDeletion deletion);
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
  int sequence;

  Aggregate({
    required this.name,
    required this.filter,
    required this.state,
    this.sequence = -1,
  }) : assert(sequence >= -1);

  Snapshot<TState> snapshot() => Snapshot(state, sequence);

  @override
  String toString() => name;
}
