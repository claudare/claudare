import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/command/command_executor.dart';
import 'package:core/src/cqrs/projection/projection_runtime.dart';

class BoundCommand<TInput> {
  final CommandExecutor executor;
  final Command<TInput> command;
  final List<ProjectionRuntime> consistentRunners;
  final List<ProjectionRuntime> eventualRunners;

  const BoundCommand({
    required this.executor,
    required this.command,
    required this.consistentRunners,
    required this.eventualRunners,
  });

  Future<void> runThrowable(TInput input) async {
    //
  }
}
