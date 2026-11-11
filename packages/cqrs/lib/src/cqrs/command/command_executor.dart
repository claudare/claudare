import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/log_player.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

class CommandExecutor {
  final EventStore _eventStore;
  final String _actor;
  final StreamReader _streamReader;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final EventRegistry _eventRegistry;

  const CommandExecutor({
    required this._eventStore,
    required this._actor,
    required this._streamReader,
    required this._timeProvider,
    required this._idGenerator,
    required this._eventRegistry,
  });

  Future<void> execute(Command command) async {
    final context = CommandContext(
      eventStore: _eventStore,
      actor: _actor,
      streamReader: _streamReader,
      eventRegistry: _eventRegistry,
      timeProvider: _timeProvider,
      idGenerator: _idGenerator,
    );

    await command.handle(context);

    final changes = context.finish();
    if (!changes.isValid()) {
      throw Exception('Changes are not valid');
    }

    if (changes.isEmpty()) return;
    await _eventStore.saveChanges(changes);
  }
}
