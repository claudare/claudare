import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/event/event_envelope.dart';

abstract interface class ProjectionSink {
  bool shouldProcess(StreamIdPattern streamIdPattern, String streamIdStr);
  void enqueue(EventEnvelope event, {void Function()? onDone});
}
