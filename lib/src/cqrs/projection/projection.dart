import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/projection/projection_checkpoint.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

import 'projection_failure_handler.dart';

/// Implement this to define a projection that can play events
/// Unfortunately Event and StreamIdData must be defined on the projection level
abstract interface class Projection<Event, StreamIdData> {
  String get name;
  StreamIdPattern<StreamIdData> get streamIdPattern;
  EventCodec<Event> get eventCodec;
  ProjectionFailureHandler get failureHandler;

  Future<void> reset();

  /// Return nil localSequence if the projection is not initialized
  /// Null value will call [reset].
  Future<ProjectionCheckpoint> checkpoint();

  /// do the application. Throwing is an error
  Future<void> apply(StreamIdData idData, Event event, EventMetadata metadata);
}
