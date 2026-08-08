import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

abstract interface class CommandContext {
  CommandStream<TEvent, TData> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  );
  void nack(String message);
  String newId();
  DateTime currentTime();
}
