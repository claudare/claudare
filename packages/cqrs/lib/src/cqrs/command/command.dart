import 'command_context_api.dart';

abstract interface class Command {
  Command();

  Future<void> handle(CommandContextApi ctx);
}
