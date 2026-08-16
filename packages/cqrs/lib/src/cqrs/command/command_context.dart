import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/command/command_stream.dart';
import 'package:cqrs/src/cqrs/event/event_codec.dart';
import 'package:cqrs/src/cqrs/event/event_codec_safe.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';
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

  CommandStream<TEvent, TParams> stream<TEvent, TParams>(
    EventCodec<TEvent> eventCodec,
    StreamRoute<TParams> streamRoute,
    TParams streamParams,
  ) {
    final streamPath = streamRoute.buildPath(streamParams);
    final safeEventCodec = EventCodecSafe(eventCodec);
    return CommandStream<TEvent, TParams>(
      _eventStore,
      _executionState,
      safeEventCodec,
      streamPath,
      streamParams,
      _timeProvider,
    );
  }

  String newId() => _idGenerator.generateId();

  DateTime currentTime() => _timeProvider.now();
}
