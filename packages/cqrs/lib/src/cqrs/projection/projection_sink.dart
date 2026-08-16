import 'package:cqrs/src/cqrs/event/applied_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';

abstract interface class ProjectionSink {
  void enqueue(EventEnvelope event, {void Function()? onDone});
  bool shouldProcess(String streamPath);
  void enqueueApplied(AppliedEvent event, {void Function()? onDone});
}
