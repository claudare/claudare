import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/command/command_codec_safe.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/command/command.dart';

class CommandExecutor {
  static const _commandCodec = CommandCodecSafe();
  final EventStore _eventStore;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  const CommandExecutor({
    required EventStore eventStore,
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
    final executionState = CommandExecutionState(locks: [], events: []);

    final context = CommandContext(
      eventStore: _eventStore,
      executionState: executionState,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
    );

    await command.handle(input, context);

    return _saveEvents<Input>(executionState, startedAt, input);
  }

  Future<List<EventEnvelope>> _saveEvents<TInput extends CommandInput>(
    CommandExecutionState executionState,
    DateTime startedAt,
    TInput input,
  ) async {
    final encoded = _commandCodec.encode(input);
    final changes = CommandChanges(
      encoded: encoded,
      startedAt: startedAt,
      completedAt: _timeProvider.now(),
      locks: executionState.locks,
      events:
          executionState.events.map((event) => event.toEventAppend()).toList(),
    );

    final appendResult = await _eventStore.saveChanges(changes);

    return List.generate(executionState.events.length, (index) {
      final order = appendResult.orders[index];
      return executionState.events[index].toEventEnvelope(
        localSequence: order.localSequence,
      );
    }, growable: false);
  }
}
