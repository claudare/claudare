import 'package:core/src/cqrs/command/command_appends.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs/command/command_side_effects.dart';
import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_codec_safe.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class CommandContext {
  final EventStoreCommand _eventStore;
  final CommandAppends _appends;
  final CommandNacker _nacker;
  final CommandSideEffects _sideEffects;

  const CommandContext({
    required EventStoreCommand eventStore,
    required CommandAppends appends,
    required CommandNacker nacker,
    required CommandSideEffects sideEffects,
  }) : _eventStore = eventStore,
       _appends = appends,
       _nacker = nacker,
       _sideEffects = sideEffects;

  CommandStream<TEvent, TData> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  ) {
    final streamId = streamIdPattern.toPath(streamData);
    final safeEventCodec = EventCodecSafe(eventCodec);
    return CommandStream<TEvent, TData>(
      _eventStore,
      _appends,
      safeEventCodec,
      20, // pagination size
      streamId,
      streamData,
      streamIdPattern,
    );
  }

  void nack(String message) {
    _nacker.nack(message);
  }

  String newId() {
    return _sideEffects.newId();
  }

  DateTime currentTime() {
    return _sideEffects.currentTime();
  }
}
