import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/log_filter.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/stream_deletion.dart';

/// Stateful [Projection] replays events asyncronously. Load method is called to
/// initialize it.
abstract interface class Projection<TEvent extends Object> {
  String get name;

  LogFilter get filter;

  /// Loads the aggregate at a given [logPosition]
  /// But how do we know the position to load at?
  Future<void> load(int logPosition);

  /// Mutates this state for [envelope].
  Future<void> apply(EventEnvelope<TEvent> envelope);

  /// Handles permanent deletion of a matching stream.
  Future<void> onStreamDeleted(StreamDeletion deletion);
}
