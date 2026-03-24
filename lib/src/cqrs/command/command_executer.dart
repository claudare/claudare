import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/command/command.dart';

class CommandExecuter {
  final EventStoreCommand eventStore;

  const CommandExecuter(this.eventStore);

  Future<List<LiveEventFull>> executeThrowable<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    return [];
  }
}
