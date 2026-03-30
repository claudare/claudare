import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/event/live_event_min.dart';

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
}
