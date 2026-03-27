import 'package:core/src/cqrs/command/command_appends.dart';
import 'package:core/src/cqrs/command/command_context.dart';
import 'package:core/src/cqrs/command/command_nacker.dart';
import 'package:core/src/cqrs/command/command_side_effects.dart';
import 'package:core/src/cqrs/command/stored_command.dart';
import 'package:core/src/cqrs/device_id.dart';
import 'package:core/src/cqrs/event/event_dependency.dart';
import 'package:core/src/cqrs/event/live_event.dart';
import 'package:core/src/cqrs/event_store/event_store_command.dart';
import 'package:core/src/cqrs/command/command.dart';
import 'package:core/src/cqrs/exception/command_execution_exception.dart';
import 'package:core/src/cqrs/exception/command_nack.dart';

class CommandExecutor {
  final EventStoreCommand eventStore;
  final CommandSideEffects sideEffects;

  final DeviceId thisDeviceId;

  const CommandExecutor({
    required this.eventStore,
    required this.sideEffects,
    required this.thisDeviceId,
  });

  Future<Iterable<LiveEventFull>> executeThrowable<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    final startedAt = sideEffects.currentTime();
    final nacker = CommandNacker();
    final dependencies = EventDependency.empty();
    final appends = CommandAppends(
      dependencies: dependencies,
      locks: [],
      appendEvents: [],
    );

    final context = CommandContext(
      eventStore:
          eventStore, // TODO: make sure its safe... just a single class? use a concrete EventStoreSafe
      appends: appends,
      nacker: nacker,
      sideEffects: sideEffects,
    );

    try {
      await command.handle(input, context);
    } on Exception catch (cause) {
      // TODO: save failed command
      await _saveFailedCommand(
        startedAt,
        command,
        input,
        StoredCommandResult.exception(exception: cause),
      );

      throw CommandExecutionException(cause.toString(), cause: cause);
    } catch (_) {
      rethrow;
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

  Future<Iterable<LiveEventFull>> _saveEvents<TInput>(
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
      completedAt: sideEffects.currentTime(),
    );

    final eventStoreAppends = StreamAppends(
      dependencies: commandAppends.dependencies,
      locks: commandAppends.locks,
      events:
          commandAppends.appendEvents
              .map((e) => e.toStoredEventCommandWrite())
              .toList(),
    );

    final appendResult = await eventStore.multiAppendEvents(
      thisDeviceId,
      issuedCommand,
      eventStoreAppends,
    );

    return Iterable.generate(commandAppends.appendEvents.length, (index) {
      final order = appendResult.orders[index];
      return commandAppends.appendEvents[index].toLiveEventFull(
        localSequence: order.localSequence,
        version: order.localVersion,
      );
    });
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
        completedAt: sideEffects.currentTime(),
      );

      await eventStore.saveFailedCommand(thisDeviceId, issuedCommand, result);
    } on Exception catch (e) {
      // do nothing... stongly log?
      // TODO: remove me: no logging is most desirable...
      print('failed to save failed command: $e');
    } catch (_) {
      rethrow;
    }
  }

  // return of some result time for easy error checking
  Future<dynamic> executeResult<TInput>(
    Command<TInput> command,
    TInput input,
  ) async {
    return [];
  }
}
