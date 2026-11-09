import 'package:cqrs/src/cqrs/event/stored_event.dart';

/// Reads a stream from an inclusive version.
typedef StreamReader = Stream<StoredEvent> Function(
  String streamPath, {
  int fromVersion,
});
