import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
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
  final EventRegistry _eventRegistry;
  final Logger _logger;

  const CommandExecutor({
    required EventStore eventStore,
    required TimeProvider timeProvider,
    required EventRegistry eventRegistry,
    required Logger logger,
  }) : _eventRegistry = eventRegistry,
       _logger = logger,
       _timeProvider = timeProvider,
       _eventStore = eventStore;

  Future<void> execute<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) async {
    final startedAt = _timeProvider.now();
    final executionState = CommandExecutionState(locks: [], events: []);

    final context = CommandContext(
      eventStore: _eventStore,
      executionState: executionState,
      eventRegistry: _eventRegistry,
      timeProvider: _timeProvider,
      logger: _logger,
    );

    await command.handle(input, context);

    if (executionState.events.isEmpty) return;
    await _saveEvents<Input>(executionState, startedAt, input);
  }

  Future<void> _saveEvents<TInput extends CommandInput>(
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
      events: executionState.events,
    );

    await _eventStore.saveChanges(changes);
  }
}
