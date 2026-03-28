import 'package:core/src/cqrs/command/command_appends.dart';
import 'package:core/src/cqrs/command/command_context.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/exception/command_execution_exception.dart';
import 'package:core/src/cqrs/exception/command_nack.dart';
import 'package:core/src/cqrs/id_generator/id_generator.dart';
import 'package:core/src/cqrs/time_provider/time_provider.dart';

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

  Future<List<LiveEventFull>> executeThrowable<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    final startedAt = _timeProvider.now();
    final nacker = CommandNacker();
    final dependencies = EventDependency.empty();
    final appends = CommandAppends(
      dependencies: dependencies,
      locks: [],
      appendEvents: [],
    );

    final context = CommandContext(
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
          command,
          input,
          StoredCommandResult.exception(exception: cause),
        );

        throw CommandExecutionException(cause.toString(), cause: cause);
      }

      Error.throwWithStackTrace(cause, stackTrace);
    }

    if (nacker.message != null) {
      await _saveFailedCommand(
        startedAt,
        command,
        input,
        StoredCommandResult.nack(reason: nacker.message!),
      );

      throw CommandNack(message: nacker.message!);
    }

    return _saveEvents<TInput>(appends, startedAt, command, input);
  }

  Future<List<LiveEventFull>> _saveEvents<TInput>(
    CommandAppends commandAppends,
    DateTime startedAt,
    Command<TInput> command,
    TInput input,
  ) async {
    final detailString = command.encodeDetail(
      input,
    ); // TODO: this needs to be made safe
    final issuedCommand = StoredCommandWrite(
      kind: command.kind,
      detail: detailString,
      startedAt: startedAt,
      completedAt: _timeProvider.now(),
    );

    final eventStoreAppends = StreamAppends(
      dependencies: commandAppends.dependencies,
      locks: commandAppends.locks,
      events:
          commandAppends.appendEvents
              .map((e) => e.toStoredEventCommandWrite())
              .toList(),
    );

    final appendResult = await _eventStore.multiAppendEvents(
      _thisDeviceId,
      issuedCommand,
      eventStoreAppends,
    );

    return List.generate(commandAppends.appendEvents.length, (index) {
      final order = appendResult.orders[index];
      return commandAppends.appendEvents[index].toLiveEventFull(
        localSequence: order.localSequence,
        version: order.localVersion,
      );
    }, growable: false);
  }

  /// saves command that fails. This never throws!
  Future<void> _saveFailedCommand<TInput>(
    DateTime startedAt,
    Command<TInput> command,
    TInput input,
    StoredCommandResult result,
  ) async {
    try {
      final detailString = command.encodeDetail(
        input,
      ); // this does not need to be safe

      final issuedCommand = StoredCommandWrite(
        kind: command.kind,
        detail: detailString,
        startedAt: startedAt,
        completedAt: _timeProvider.now(),
      );

      await _eventStore.saveFailedCommand(_thisDeviceId, issuedCommand, result);
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
