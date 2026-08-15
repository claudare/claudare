import 'package:cqrs/src/cqrs/command/command_stream.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

abstract interface class CommandContext {
  CommandStream<TEvent, TData> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  );
  String newId();
  DateTime currentTime();
}
