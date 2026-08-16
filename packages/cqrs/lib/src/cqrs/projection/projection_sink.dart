import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

abstract interface class ProjectionSink {
  // fast path
  void enqueue(EventEnvelope event, {void Function()? onDone});
  bool shouldProcess(StreamIdPattern streamIdPattern, String streamIdStr);
  // slow path
  bool shouldProcessString(String streamIdStr);
  void enqueueApplied(AppliedEvent event, {void Function()? onDone});
}
