import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

import 'projection_failure_handler.dart';

/// Implement this to define a projection that can play events
/// Unfortunately Event and StreamParams must be defined on the projection level
abstract interface class Projection<Event, StreamParams> {
  String get name;
  StreamRoute<StreamParams> get streamRoute;
  EventCodec<Event> get eventCodec;
  ProjectionFailureHandler get failureHandler;

  Future<void> reset();

  /// do the application. Throwing is an error
  Future<void> apply(
    StreamParams streamParams,
    Event event,
    EventMetadata metadata,
  );
}
