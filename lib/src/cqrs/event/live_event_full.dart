import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

// the better name is EventBusEnvelope
// but there is no bus in the application
// RuntimeEventEnvelope?
class LiveEventFull<Event, IdData> {
  final StreamIdPattern streamIdPattern;
  final String streamIdStr;
  final IdData streamIdData;

  final Event event;
  final EventMetadata metadata;

  const LiveEventFull({
    required this.streamIdStr,
    required this.streamIdData,
    required this.streamIdPattern,
    required this.event,
    required this.metadata,
  });
}
