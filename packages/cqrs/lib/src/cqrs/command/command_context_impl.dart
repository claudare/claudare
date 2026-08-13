import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:cqrs/src/cqrs/command/command_appends.dart';
import 'package:cqrs/src/cqrs/command/command_nacker.dart';
import 'package:cqrs/src/cqrs/command/command_stream.dart';
import 'package:cqrs/src/cqrs/command/command_stream_impl.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:time_provider/time_provider.dart';

class CommandContextImpl implements CommandContext {
  final EventStoreCommand _eventStore;
  final CommandAppends _appends;
  final CommandNacker _nacker;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final int _pageSize;

  const CommandContextImpl({
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

  @override
  CommandStream<TEvent, TData> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  ) {
    final streamId = streamIdPattern.toPath(streamData);
    final safeEventCodec = EventCodecSafe(eventCodec);
    return CommandStreamImpl<TEvent, TData>(
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

  @override
  void nack(String message) {
    _nacker.nack(message);
  }

  @override
  String newId() {
    return _idGenerator.generateId();
  }

  @override
  DateTime currentTime() {
    return _timeProvider.now();
  }
}
