import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/runtime_repo/runtime_repo.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';

/// Dependencies shared by all CQRS runtimes.
///
/// Runtime-specific dependencies do not belong here.
class CqrsRuntimeDependencies {
  final EventStore eventStore;
  final RuntimeRepo runtimeRepo;
  final Logger logger;

  final IdGenerator idGenerator;
  final TimeProvider timeProvider;

  const CqrsRuntimeDependencies({
    required this.eventStore,
    required this.runtimeRepo,
    required this.logger,
    required this.idGenerator,
    required this.timeProvider,
  });
}
