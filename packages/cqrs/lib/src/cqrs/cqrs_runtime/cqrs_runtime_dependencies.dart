import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

/// Dependencies shared by all CQRS runtimes.
///
/// Runtime-specific dependencies do not belong here.
class CqrsRuntimeDependencies {
  final EventStore eventStore;
  final RuntimeDatabase runtimeDatabase;
  final Logger logger;

  final IdGenerator idGenerator;
  final TimeProvider timeProvider;

  const CqrsRuntimeDependencies({
    required this.eventStore,
    required this.runtimeDatabase,
    required this.logger,
    required this.idGenerator,
    required this.timeProvider,
  });
}
