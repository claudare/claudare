import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

/// Implement [StatelessProjection] to resolve a projection on demand.
/// Will load and replay all events on the pattern.
/// This may be dangerous to use
/// TODO: this is just an idea for now
abstract interface class StatelessProjection<Event, StreamIdData> {
  StreamIdPattern<StreamIdData> get streamIdPattern;
  EventCodec<Event> get eventCodec;

  /// do the application. Throwing is an error
  Future<void> apply(StreamIdData idData, Event event, EventMetadata metadata);
}
