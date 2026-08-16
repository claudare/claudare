import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/command/command_stream.dart';
import 'package:cqrs/src/cqrs/command/command_stream_impl.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/stream_id_pattern/stream_id_pattern.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

class CommandContext {
  final EventStore _eventStore;
  final CommandExecutionState _executionState;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  const CommandContext({
    required EventStore eventStore,
    required CommandExecutionState executionState,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
  }) : _eventStore = eventStore,
       _executionState = executionState,
       _timeProvider = timeProvider,
       _idGenerator = idGenerator;

  CommandStream<TEvent, TData> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  ) {
    final streamId = streamIdPattern.toPath(streamData);
    final safeEventCodec = EventCodecSafe(eventCodec);
    return CommandStreamImpl<TEvent, TData>(
      _eventStore,
      _executionState,
      safeEventCodec,
      streamId,
      streamData,
      streamIdPattern,
      _timeProvider,
    );
  }

  String newId() => _idGenerator.generateId();

  DateTime currentTime() => _timeProvider.now();
}
