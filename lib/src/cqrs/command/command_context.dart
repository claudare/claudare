import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs/event/event_pack.dart';

class CommandContext {
  CommandStream<TEvents> stream<TEvents, TData>(
    EventPack<TEvents, TData> eventPack,
    TData streamData,
  ) {
    return CommandStream<TEvents>();
  }

  void nack(String message) {
    //
  }

  String newId() {
    return "";
  }
}
