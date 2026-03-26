import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class CommandContext {
  CommandStream<TEvent> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  ) {
    return CommandStream<TEvent>();
  }

  void nack(String message) {
    //
  }

  String newId() {
    return "";
  }

  DateTime now() {
    // TODO: use the custom context
    return DateTime.now();
  }
}
