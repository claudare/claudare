import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/command/command.dart';

class CommandExecutor {
  final EventStoreCommand eventStore;

  const CommandExecutor(this.eventStore);

  Future<List<LiveEventFull>> executeThrowable<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    return [];
  }

  // return of some result time for easy error checking
  Future<dynamic> executeResult<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    return [];
  }
}
