import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';

class CommandExecutionEvent<Event, Params> {
  final String streamPath;
  final Params streamParams;

  final Event runtimeEvent;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const CommandExecutionEvent({
    required this.streamPath,
    required this.streamParams,

    required this.runtimeEvent,
    required this.encodedEvent,
    required this.occuredAt,
  });

  EventAppend toEventAppend() {
    return EventAppend(
      streamPath: streamPath,
      encodedEvent: encodedEvent,
      occuredAt: occuredAt,
    );
  }

  EventEnvelope toEventEnvelope({required int localSequence}) {
    return EventEnvelope(
      streamPath: streamPath,
      streamParams: streamParams,
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
