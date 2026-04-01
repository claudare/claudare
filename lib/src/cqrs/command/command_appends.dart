import 'package:core/src/cqrs/event/encoded_event.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/event_metadata.dart';
import 'package:core/src/cqrs/event/live_event_full.dart';
import 'package:core/src/cqrs/event/stored_event_command_write.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

// TODO: rename this to this a EventBusEnvelope, include mutatable localSequence
// which is set my event store. Mutability is okay here
// it makes it simple. it is assert validated for db testing
class CommandAppendEvent<Event, IdData> {
  final StreamIdPattern<IdData> streamIdPattern;
  final String streamIdStr;
  final IdData streamIdData;

  final Event runtimeEvent;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const CommandAppendEvent({
    required this.streamIdPattern,
    required this.streamIdStr,
    required this.streamIdData,

    required this.runtimeEvent,
    required this.encodedEvent,
    required this.occuredAt,
  });

  StoredEventCommandWrite toStoredEventCommandWrite() {
    return StoredEventCommandWrite(
      streamId: streamIdStr,
      encodedEvent: encodedEvent,
      occuredAt: occuredAt,
    );
  }

  LiveEventFull toLiveEventFull({required int localSequence}) {
    return LiveEventFull(
      streamIdPattern: streamIdPattern,
      streamIdStr: streamIdStr,
      streamIdData: streamIdData,
      event: runtimeEvent,
      metadata: EventMetadata(
        occuredAt: occuredAt,
        localSequence: localSequence,
      ),
    );
  }
}

class CommandAppends {
  final EventDependency dependencies;
  final List<StreamLocalLock> locks;
  final List<CommandAppendEvent> appendEvents; // could be dynamic?

  const CommandAppends({
    required this.dependencies,
    required this.locks,
    required this.appendEvents,
  });
}
