import 'command_context.dart';

abstract interface class Command<Input> {
  const Command();

  Future<void> handle(Input input, CommandContext ctx);
}
