import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/event/stored_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class CommandAppendEvent<Event, IdData> {
  final String streamIdStr;
  final IdData streamIdData;

  /// momento is not needed here. event is already something in memory decoded.
  /// anothe reason to move it out
  final StreamIdPattern<IdData> streamIdPattern;
  final Event event;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const CommandAppendEvent({
    required this.streamIdStr,
    required this.streamIdData,
    required this.streamIdPattern,
    required this.event,
    required this.encodedEvent,
    required this.occuredAt,
  });

  StoredEventCommandWrite toStoredEventCommandWrite() {
    return StoredEventCommandWrite(
      streamId: streamIdStr,
      kind: encodedEvent.kind,
      detail: encodedEvent.detail,
      occuredAt: occuredAt,
    );
  }

  LiveEventFull toLiveEventFull({
    required int localSequence,
    required int version,
  }) {
    return LiveEventFull(
      streamIdStr: streamIdStr,
      streamIdData: streamIdData,
      streamIdPattern: streamIdPattern,
      event: event,
      occuredAt: occuredAt,
      localSequence: localSequence,
      version: version,
    );
  }
}

class CommandAppends {
  final EventDependency dependencies;
  final List<StreamLock> locks;
  final List<CommandAppendEvent> appendEvents; // could be dynamic?

  const CommandAppends({
    required this.dependencies,
    required this.locks,
    required this.appendEvents,
  });
}
