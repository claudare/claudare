import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/snapshotter.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

/// Defines event selection and mutable state for aggregate resolution.
abstract interface class Aggregate<TEvent extends Object, TState> {
  /// Version used to invalidate snapshots when aggregate behavior changes.
  int get version;

  /// Specifies which stream this aggregate uses. When the aggregate is resolved,
  /// only the compatible events will reach apply.
  ///
  /// However, its still beneficial to implement a proper canApply in order to
  /// implement subAggregates.
  StreamRoute get streamRoute;

  /// Optional snapshotter used to avoid replaying the entire event stream.
  /// It would be beneficial to make this configurable at constructor level.
  Snapshotter<TState>? get snapshotter;

  /// Returns the initial state of the aggregate. Each resolution needs fresh
  /// state because apply mutates it.
  TState initialState();

  /// Determines whether this envelope can be applied. Returning false skips the
  /// apply call.
  ///
  /// In most cases this is not needed, as only relevant events in the
  /// streamRoute will be passed along
  bool canApply(EventEnvelope<TEvent> envelope);

  /// Mutates state in place. Do not reassign the state parameter!
  /// Assigning state = { ... } does not update the aggregate's state.
  void apply(TState state, EventEnvelope<TEvent> envelope);
}
