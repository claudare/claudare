import 'package:core/src/cqrs/event/live_event_full.dart';
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
