import 'package:core/src/cqrs.dart';
import 'package:core/src/cqrs/event/live_event_full.dart';

abstract interface class ProjectionSink {
  bool shouldProcess(StreamIdPattern streamIdPattern, String streamIdStr);
  void enqueue(LiveEventFull event, {void Function()? onDone});
}
