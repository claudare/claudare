import 'command_context.dart';

abstract interface class Command {
  Command();

  Future<void> handle(CommandContext ctx);
}
