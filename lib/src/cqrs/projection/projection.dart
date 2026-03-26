import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

/// Implement this to define a projection that can play events
/// Unfortunately Event and StreamIdData must be defined on the projection level
abstract interface class Projection<Event, StreamIdData> {
  String get name;
  StreamIdPattern<StreamIdData> get streamIdPattern;
  EventCodec<Event> get eventCodec;

  Future<void> reset();

  /// return zero version if there is none
  Future<int> getLocalSequence();

  /// do the application. Throwing is an error
  Future<void> apply(StreamIdData idData, Event event, EventMetadata metadata);
}

/// Factory function to infer types. But this does not allow dependency injection
Projection<E, S> createProjection<E, S>({
  required String name,
  required StreamIdPattern<S> streamIdPattern,
  required EventCodec<E> eventCodec,
  required Future<void> Function(S idData, E event, EventMetadata metadata)
  apply,
  required Future<void> Function() reset,
  required Future<int> Function() getLocalSequence,
}) {
  return _FunctionalProjection(
    name: name,
    streamIdPattern: streamIdPattern,
    eventCodec: eventCodec,
    apply: apply,
    reset: reset,
    getLocalSequence: getLocalSequence,
  );
}

class _FunctionalProjection<E, S> implements Projection<E, S> {
  @override
  final String name;
  @override
  final StreamIdPattern<S> streamIdPattern;
  @override
  final EventCodec<E> eventCodec;

  final Future<void> Function(S idData, E event, EventMetadata metadata) _apply;
  final Future<void> Function() _reset;
  final Future<int> Function() _getLocalSequence;

  _FunctionalProjection({
    required this.name,
    required this.streamIdPattern,
    required this.eventCodec,
    required Future<void> Function(S, E, EventMetadata) apply,
    required Future<void> Function() reset,
    required Future<int> Function() getLocalSequence,
  }) : _apply = apply,
       _reset = reset,
       _getLocalSequence = getLocalSequence;

  @override
  Future<void> apply(S idData, E event, EventMetadata metadata) =>
      _apply(idData, event, metadata);

  @override
  Future<void> reset() => _reset();

  @override
  Future<int> getLocalSequence() => _getLocalSequence();
}
