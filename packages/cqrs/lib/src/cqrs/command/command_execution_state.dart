import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class CommandExecutionEvent<Event, IdData> {
  // TODO: keep only the streamId as a String...
  final StreamIdPattern<IdData> streamIdPattern;
  final String streamIdStr;
  final IdData streamIdData;

  final Event runtimeEvent;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const CommandExecutionEvent({
    required this.streamIdPattern,
    required this.streamIdStr,
    required this.streamIdData,

    required this.runtimeEvent,
    required this.encodedEvent,
    required this.occuredAt,
  });

  EventAppend toEventAppend() {
    return EventAppend(
      streamId: streamIdStr,
      encodedEvent: encodedEvent,
      occuredAt: occuredAt,
    );
  }

  EventEnvelope toEventEnvelope({required int localSequence}) {
    return EventEnvelope(
      streamIdPattern: streamIdPattern,
      streamIdStr: streamIdStr,
      streamIdData: streamIdData,
      event: runtimeEvent,
      occuredAt: occuredAt,
      localSequence: localSequence,
    );
  }
}

class CommandExecutionState {
  final List<StreamLocalLock> locks;
  final List<CommandExecutionEvent> events;

  const CommandExecutionState({required this.locks, required this.events});
}
