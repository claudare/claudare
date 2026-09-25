import 'package:cqrs/src/cqrs/command/staged_command.dart';
import 'package:cqrs/src/cqrs/event/staged_event.dart';

/// A complete command and its ordered events at the replication boundary.
class CommandBundle {
  final StagedCommand command;
  final List<StagedEvent> events;

  const CommandBundle({required this.command, required this.events});

  bool _checkEventCount() {
    return events.length == command.eventCount;
  }

  bool _checkIds() {
    return events.every((e) => e.eventId.commandId == command.commandId);
  }

  bool _checkEventIndexes() {
    for (var index = 0; index < events.length; index++) {
      if (events[index].eventId.index != index) return false;
    }
    return true;
  }

  bool get isValid => _checkEventCount() && _checkIds() && _checkEventIndexes();
}
