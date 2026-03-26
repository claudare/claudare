import 'package:core/src/cqrs/command/command_side_effects.dart';
import 'package:core/src/cqrs/command/command_stream.dart';
import 'package:core/src/cqrs/event/event_codec.dart';
import 'package:core/src/cqrs/event/event_codec_safe.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/exception/command_already_nacked_exception.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class CommandContext {
  final EventStoreCommand _eventStore;
  final _appends = StreamAppends(
    dependencies: EventDependency(),
    locks: [],
    events: [],
  );
  final CommandSideEffects _sideEffects;

  String? _nackMessage;
  late final DateTime startedAt;

  CommandContext({
    required CommandSideEffects sideEffects,
    required EventStoreCommand eventStore,
  }) : _sideEffects = sideEffects,
       _eventStore = eventStore {
    startedAt = _sideEffects.currentTime();
  }

  CommandStream<TEvent> stream<TEvent, TData>(
    EventCodec<TEvent> eventCodec,
    StreamIdPattern<TData> streamIdPattern,
    TData streamData,
  ) {
    final streamId = streamIdPattern.toPath(streamData);
    final safeEventCodec = EventCodecSafe(eventCodec);
    return CommandStream<TEvent>(
      _eventStore,
      _appends,
      safeEventCodec,
      20, // pagination size
      streamId,
    );
  }

  void nack(String message) {
    if (_nackMessage != null) {
      throw CommandAlreadyNackedException();
    }

    _nackMessage = message;
  }

  String newId() {
    return _sideEffects.newId();
  }

  DateTime currentTime() {
    return _sideEffects.currentTime();
  }
}
