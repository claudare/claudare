import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

abstract interface class ProjectionSink {
  bool shouldProcess(StreamIdPattern streamIdPattern, String streamIdStr);
  void enqueue(EventEnvelope event, {void Function()? onDone});
}
