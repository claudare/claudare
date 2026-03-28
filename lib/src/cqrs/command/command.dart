import 'command_input.dart';
import 'command_context.dart';

abstract interface class Command<Input extends CommandInput> {
  const Command();

  Future<void> handle(Input input, CommandContext ctx);
}
