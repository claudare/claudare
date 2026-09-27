import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/stream_reader.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:time_provider/time_provider.dart';

class CommandExecutor {
  final EventStore _eventStore;
  final String _actor;
  final StreamReader _streamReader;
  final TimeProvider _timeProvider;
  final EventRegistry _eventRegistry;
  final Logger _logger;

  const CommandExecutor({
    required this._eventStore,
    required this._actor,
    required this._streamReader,
    required this._timeProvider,
    required this._eventRegistry,
    required this._logger,
  });

  Future<void> execute(Command command) async {
    final context = CommandContext(
      eventStore: _eventStore,
      actor: _actor,
      streamReader: _streamReader,
      eventRegistry: _eventRegistry,
      timeProvider: _timeProvider,
      logger: _logger,
    );

    await command.handle(context);

    final changes = context.finish();
    if (changes.events.isEmpty) return;
    await _eventStore.saveChanges(changes);
  }
}
