import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/projection/projection_checkpoint.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

/// Implement this to define a projection that can play events
/// Unfortunately Event and StreamIdData must be defined on the projection level
abstract interface class Projection<Event, StreamIdData> {
  String get name;
  StreamIdPattern<StreamIdData> get streamIdPattern;
  EventCodec<Event> get eventCodec;

  Future<void> reset();

  /// return zero version if there is none
  Future<ProjectionCheckpoint> checkpoint();

  /// do the application. Throwing is an error
  Future<void> apply(StreamIdData idData, Event event, EventMetadata metadata);
}
