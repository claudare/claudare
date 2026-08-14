import 'package:cqrs/src/cqrs/command/command_context_impl.dart';
import 'package:cqrs/src/cqrs/command/stored_command_write.dart';
import 'package:cqrs/src/cqrs/event/event_envelope.dart';
import 'package:cqrs/src/cqrs/exception/concurrency_problem.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

import 'package:cqrs/src/cqrs/command/command_appends.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/command/command_nacker.dart';
import 'package:cqrs/src/cqrs/command/command_result.dart';
import 'package:cqrs/src/cqrs/command/encoded_command.dart';
import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/event/event_dependency.dart';
import 'package:cqrs/src/cqrs/event_store/event_store_command.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/exception/command_execution_exception.dart';
import 'package:cqrs/src/cqrs/exception/command_nack.dart';
import 'package:cqrs/src/cqrs/exception/command_serialization_exception.dart';
import 'package:cqrs/src/cqrs/exception/event_store_exception.dart';

class CommandExecutor {
  final EventStoreCommand _eventStore;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  final DeviceId _thisDeviceId;

  const CommandExecutor({
    required EventStoreCommand eventStore,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
    required DeviceId thisDeviceId,
  }) : _idGenerator = idGenerator,
       _timeProvider = timeProvider,
       _eventStore = eventStore,
       _thisDeviceId = thisDeviceId;

  Future<List<EventEnvelope>> executeThrowable<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) async {
    final startedAt = _timeProvider.now();
    final nacker = CommandNacker();
    final dependencies = EventDependency.empty();
    final appends = CommandAppends(
      dependencies: dependencies,
      locks: [],
      appendEvents: [],
    );

    final context = CommandContextImpl(
      eventStore: _eventStore,
      appends: appends,
      nacker: nacker,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
    );

    try {
      await command.handle(input, context);
    } on ConcurrencyProblem {
      rethrow;
    } on EventStoreException {
      rethrow;
    } on Exception catch (cause) {
      await _saveFailedCommand(
        startedAt,
        input,
        CommandResult.exception(exception: cause),
      );

      throw CommandExecutionException(cause.toString(), cause: cause);
    }

    if (nacker.message != null) {
      await _saveFailedCommand(
        startedAt,
        input,
        CommandResult.nack(reason: nacker.message!),
      );

      throw CommandNack(message: nacker.message!);
    }

    return _saveEvents<Input>(appends, startedAt, input);
  }

  EncodedCommand _encodeCommand<Input extends CommandInput>(Input input) {
    try {
      return EncodedCommand(kind: input.kind, bytes: input.encode());
    } on Exception catch (e, st) {
      Error.throwWithStackTrace(
        CommandSerializationException(e.toString(), error: e),
        st,
      );
    } catch (error, stackTrace) {
      if (isJsonExceptionLikeError(error)) {
        Error.throwWithStackTrace(
          CommandSerializationException(error.toString(), error: error),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<List<EventEnvelope>> _saveEvents<TInput extends CommandInput>(
    CommandAppends commandAppends,
    DateTime startedAt,
    TInput input,
  ) async {
    final encoded = _encodeCommand(input);
    final issuedCommand = StoredCommandWrite(
      deviceId: _thisDeviceId,
      encoded: encoded,
      startedAt: startedAt,
      completedAt: _timeProvider.now(),
      result: CommandResult.success(),
    );

    final eventStoreAppends = StreamAppends(
      dependencies: commandAppends.dependencies,
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

  Future<void> _saveFailedCommand<Input extends CommandInput>(
    DateTime startedAt,
    Input input,
    CommandResult result,
  ) async {
    final encoded = _encodeCommand(input);

    final issuedCommand = StoredCommandWrite(
      deviceId: _thisDeviceId,
      encoded: encoded,
      startedAt: startedAt,
      completedAt: _timeProvider.now(),
      result: result,
    );

    await _eventStore.saveChanges(issuedCommand, StreamAppends.empty());
  }
}
