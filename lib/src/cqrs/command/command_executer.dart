import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:core/src/cqrs/command/command.dart';

class CommandExecuter {
  final EventStore eventStore;

  const CommandExecuter(this.eventStore);

  // TODO: live event is returned
  Future<void> executeThrowable<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    //
  }
}
