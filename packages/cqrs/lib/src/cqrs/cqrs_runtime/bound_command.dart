import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/projection/projection_router.dart';

class BoundCommand<Input extends CommandInput> {
  final CommandExecutor _executor;
  final Command<Input> _command;
  final ProjectionRouter _consistentRouter;
  final ProjectionRouter _eventualRouter;

  const BoundCommand({
    required CommandExecutor executor,
    required Command<Input> command,
    required ProjectionRouter consistentRouter,
    required ProjectionRouter eventualRouter,
  }) : _eventualRouter = eventualRouter,
       _consistentRouter = consistentRouter,
       _command = command,
       _executor = executor;

  // run is a bad name
  Future<void> runThrowable(Input input) async {
    final liveEvents = await _executor.executeThrowable(_command, input);

    _eventualRouter.dispatch(liveEvents);
    await _consistentRouter.dispatchAndWait(liveEvents);
  }
}

typedef BoundCommandFn<Input extends CommandInput> =
    Future<void> Function(Input input);
