import 'package:core/src/cqrs/command/command_appends.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_codec_safe.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/id_generator/id_generator.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:core/src/cqrs/time_provider/time_provider.dart';

class CommandContext {
  final EventStoreCommand _eventStore;
  final CommandAppends _appends;
  final CommandNacker _nacker;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final int _pageSize;

  const CommandContext({
    required EventStoreCommand eventStore,
    required CommandAppends appends,
    required CommandNacker nacker,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
    required int pageSize,
  }) : _eventStore = eventStore,
       _appends = appends,
       _nacker = nacker,
       _timeProvider = timeProvider,
       _idGenerator = idGenerator,
       _pageSize = pageSize;

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
      _pageSize,
      streamId,
      streamData,
      streamIdPattern,
      _timeProvider,
    );
  }

  void nack(String message) {
    _nacker.nack(message);
  }

  String newId() {
    return _idGenerator.generateId();
  }

  DateTime currentTime() {
    return _timeProvider.now();
  }
}
