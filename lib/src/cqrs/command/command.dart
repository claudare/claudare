import 'package:core/src/cqrs/command/command_context.dart';

abstract class Command<TInput> {
  const Command();

  String get kind;

  String encodeDetail(TInput input);

  /// TODO: parsing is not needed... TInput could be forced to define toJson() or toString()
  TInput parseDetail(String str);

  Future<void> handle(TInput input, CommandContext ctx);
}
