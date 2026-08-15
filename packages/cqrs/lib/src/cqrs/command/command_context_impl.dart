import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:cqrs/src/cqrs/command/command_appends.dart';
import 'package:cqrs/src/cqrs/command/command_stream.dart';
import 'package:cqrs/src/cqrs/command/command_stream_impl.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:time_provider/time_provider.dart';

class CommandContextImpl implements CommandContext {
  final EventStore _eventStore;
  final CommandAppends _appends;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  const CommandContextImpl({
    required EventStore eventStore,
    required CommandAppends appends,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
  }) : _eventStore = eventStore,
       _appends = appends,
       _timeProvider = timeProvider,
       _idGenerator = idGenerator;

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
      streamId,
      streamData,
      streamIdPattern,
      _timeProvider,
    );
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
