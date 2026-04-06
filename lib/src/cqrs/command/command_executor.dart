import 'dart:convert';

import 'package:core/src/cqrs/command/command_context_impl.dart';
import 'package:core/src/cqrs/command/stored_command_write.dart';
import 'package:core/src/cqrs/event/event_envelope.dart';
import 'package:core/src/id_generator/id_generator.dart';
import 'package:core/src/time_provider/time_provider.dart';

import 'package:core/src/cqrs/command/command_appends.dart';
import 'package:core/src/cqrs/command/command_context.dart';
import 'package:core/src/cqrs/command/command_input.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs/command/command_result.dart';
import 'package:core/src/cqrs/command/encoded_command.dart';
import 'package:core/src/device_id.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/exception/command_execution_exception.dart';
import 'package:core/src/cqrs/exception/command_nack.dart';
import 'package:core/src/cqrs/exception/command_serialization_exception.dart';

import '../json_error.dart';

class CommandExecutor {
  final EventStoreCommand _eventStore;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;

  final DeviceId _thisDeviceId;
  final int _pageSize;

  const CommandExecutor({
    required EventStoreCommand eventStore,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
    required DeviceId thisDeviceId,
    required int pageSize,
  }) : _idGenerator = idGenerator,
       _timeProvider = timeProvider,
       _eventStore = eventStore,
       _thisDeviceId = thisDeviceId,
       _pageSize = pageSize;

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
      pageSize: _pageSize,
    );

    try {
      await command.handle(input, context);
    } catch (cause, stackTrace) {
      if (cause is Exception) {
        await _saveFailedCommand(
          startedAt,
          input,
          CommandResult.exception(exception: cause),
        );

        throw CommandExecutionException(cause.toString(), cause: cause);
      }

      Error.throwWithStackTrace(cause, stackTrace);
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
      return EncodedCommand(
        kind: input.kind,
        detail: jsonEncode(input.toJson()),
      );
    } catch (e, st) {
      if (JsonError.isJsonLikeError(e)) {
        Error.throwWithStackTrace(
          CommandSerializationException(e.toString(), error: e),
          st,
        );
      }

      if (e is Exception) {
        Error.throwWithStackTrace(
          CommandSerializationException(e.toString(), error: e),
          st,
        );
      }

      Error.throwWithStackTrace(e, st);
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

  /// saves command that fails. This never throws!
  Future<void> _saveFailedCommand<Input extends CommandInput>(
    DateTime startedAt,
    Input input,
    CommandResult result,
  ) async {
    try {
      final encoded = _encodeCommand(input);

      final issuedCommand = StoredCommandWrite(
        deviceId: _thisDeviceId,
        encoded: encoded,
        startedAt: startedAt,
        completedAt: _timeProvider.now(),
        result: result,
      );

      await _eventStore.saveChanges(issuedCommand, StreamAppends.empty());
    } on Exception catch (e) {
      // do nothing... stongly log?
      // TODO: remove me: no logging is most desirable...
      print('failed to save failed command: $e');
    } catch (_) {
      rethrow;
    }
  }

  // return of some result time for easy error checking
  // Future<dynamic> executeResult<TInput>(
  //   Command<TInput> command,
  //   TInput input,
  // ) async {
  //   return [];
  // }
}
