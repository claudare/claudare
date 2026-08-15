import 'package:cqrs/src/cqrs/command/command_context_impl.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

import 'package:cqrs/src/cqrs/command/command_appends.dart';
import 'package:cqrs/src/cqrs/command/command_codec_safe.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/command/command.dart';

class CommandExecutor {
  static const _commandCodec = CommandCodecSafe();
  final EventStoreCommand _eventStore;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  const CommandExecutor({
    required EventStoreCommand eventStore,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
  }) : _idGenerator = idGenerator,
       _timeProvider = timeProvider,
       _eventStore = eventStore;

  Future<List<EventEnvelope>> executeThrowable<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) async {
    final startedAt = _timeProvider.now();
    final appends = CommandAppends(locks: [], appendEvents: []);

    final context = CommandContextImpl(
      eventStore: _eventStore,
      appends: appends,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
    );

    await command.handle(input, context);

    return _saveEvents<Input>(appends, startedAt, input);
  }

  Future<List<EventEnvelope>> _saveEvents<TInput extends CommandInput>(
    CommandAppends commandAppends,
    DateTime startedAt,
    TInput input,
  ) async {
    final encoded = _commandCodec.encode(input);
    final issuedCommand = StoredCommandWrite(
      encoded: encoded,
      startedAt: startedAt,
      completedAt: _timeProvider.now(),
    );

    final eventStoreAppends = StreamAppends(
      localLocks: commandAppends.locks,
      events:
          commandAppends.appendEvents
              .map((e) => e.toStoredEventCommandWrite())
              .toList(),
    );

    final appendResult = await _eventStore.saveChanges(
      issuedCommand,
      eventStoreAppends,
    );

    return List.generate(commandAppends.appendEvents.length, (index) {
      final order = appendResult.orders[index];
      return commandAppends.appendEvents[index].toEventEnvelope(
        localSequence: order.localSequence,
      );
    }, growable: false);
  }
}
