import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

// [EventEnvelope] is a container of runtime defined event data.
// It is used in routing of events to correct projections. Currently is it NOT
// sent to the replication engine, as serialized data is not available.
// Maybe need to add EncodedEvent to this...
class EventEnvelope<Event, IdData> {
  final StreamIdPattern streamIdPattern;
  final String streamIdStr;
  final IdData streamIdData;

  final Event event;
  final EventMetadata metadata;
  final int localSequence;

  const EventEnvelope({
    required this.streamIdStr,
    required this.streamIdData,
    required this.streamIdPattern,
    required this.event,
    required this.metadata,
    required this.localSequence,
  });

  @override
  toString() =>
      'EventEnvelope(streamIdStr: $streamIdStr, streamIdData: $streamIdData, streamIdPattern: $streamIdPattern, event: $event, metadata: $metadata, localSequence: $localSequence)';
}
