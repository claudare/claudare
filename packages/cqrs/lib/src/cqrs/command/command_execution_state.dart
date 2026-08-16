import 'package:cqrs/src/cqrs/event/encoded_event.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';

class CommandExecutionEvent {
  final String streamPath;
  final EncodedEvent encodedEvent;
  final DateTime occuredAt;

  const CommandExecutionEvent({
    required this.streamPath,
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
      encodedEvent: encodedEvent,
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
