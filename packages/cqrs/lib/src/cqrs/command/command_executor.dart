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
    required EventStore eventStore,
    required String actor,
    required StreamReader streamReader,
    required TimeProvider timeProvider,
    required EventRegistry eventRegistry,
    required Logger logger,
  }) : _eventRegistry = eventRegistry,
       _actor = actor,
       _logger = logger,
       _timeProvider = timeProvider,
       _streamReader = streamReader,
       _eventStore = eventStore;

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
