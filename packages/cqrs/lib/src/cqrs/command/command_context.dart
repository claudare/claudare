import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command_execution_state.dart';
import 'package:cqrs/src/cqrs/command/command_stream.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

class CommandContext {
  final EventStore _eventStore;
  final CommandExecutionState _executionState;
  final EventRegistry _eventRegistry;
  final TimeProvider _timeProvider;
  final IdGenerator _idGenerator;
  final Logger _logger;

  const CommandContext({
    required EventStore eventStore,
    required CommandExecutionState executionState,
    required EventRegistry eventRegistry,
    required TimeProvider timeProvider,
    required IdGenerator idGenerator,
    required Logger logger,
  }) : _eventStore = eventStore,
       _executionState = executionState,
       _eventRegistry = eventRegistry,
       _timeProvider = timeProvider,
       _idGenerator = idGenerator,
       _logger = logger;

  Logger get logger => _logger;

  CommandStream<TEvent> stream<TEvent extends Object>(String streamPath) {
    return CommandStream<TEvent>(
      _eventStore,
      _executionState,
      _eventRegistry,
      streamPath,
      _timeProvider,
    );
  }

  String newId() => _idGenerator.generateId();

  DateTime currentTime() => _timeProvider.now();
}
