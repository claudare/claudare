import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';

class CommandExecutionState {
  final List<StreamLock> locks;
  final List<EventAppend> events;

  const CommandExecutionState({required this.locks, required this.events});
}
