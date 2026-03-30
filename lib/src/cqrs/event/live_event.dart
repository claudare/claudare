import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/projection/projection_checkpoint.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class LiveEventMin<Event, IdData> {
  final StreamIdPattern streamIdPattern;
  final String streamIdStr;
  final IdData streamIdData;

  final Event event;
  final DateTime occuredAt;

  const LiveEventMin({
    required this.streamIdPattern,
    required this.streamIdStr,
    required this.streamIdData,

    required this.event,
    required this.occuredAt,
  });

  LiveEventFull<Event, IdData> toFull({required int localSequence}) {
    return LiveEventFull(
      streamIdStr: streamIdStr,
      streamIdData: streamIdData,
      streamIdPattern: streamIdPattern,
      event: event,
      occuredAt: occuredAt,
      localSequence: localSequence,
    );
  }
}

// TODO: this should hold actual classes
// things like checkpoint, eventMetadata
class LiveEventFull<Event, IdData> extends LiveEventMin<Event, IdData> {
  final int localSequence;

  const LiveEventFull({
    required super.streamIdStr,
    required super.streamIdData,
    required super.streamIdPattern,
    required super.event,
    required super.occuredAt,
    required this.localSequence,
  });

  EventMetadata get eventMetadata =>
      EventMetadata(occuredAt: occuredAt, localSequence: localSequence);

  ProjectionCheckpoint get checkpoint =>
      ProjectionCheckpoint(localSequence: localSequence);
}
