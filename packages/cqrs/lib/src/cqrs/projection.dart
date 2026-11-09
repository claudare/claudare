import 'package:cqrs/src/cqrs/aggregate.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/stream_deletion.dart';

/// [Projection] is a stateful [Aggregate]. It replays events asyncronously and
/// can durably store its state.
abstract interface class Projection<TEvent extends Object> {
  String get name;

  LogFilter get filter;

  /// Loads the aggregate and returns last seen logPosition.
  /// [load] is always called first.
  /// This is a good place to initialize databases.
  /// Return -1 no events were applied or when the aggregate is not presisted.
  Future<int> load();

  /// Mutates this state for [envelope].
  Future<void> apply(EventEnvelope<TEvent> envelope);

  /// Handles permanent deletion of a matching stream.
  Future<void> onStreamDeleted(StreamDeletion deletion);
}
