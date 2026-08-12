import 'package:core/src/cqrs/cqrs_runtime/runtime_repo/runtime_repo.dart';
import 'package:core/src/cqrs/event_store/event_store.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:claudare_logging/claudare_logging.dart';

/// A generic config shared between all runtimes.
/// Any custom conguration options do not belong here!
class CqrsRuntimeConfig {
  // other common dependencies such as Databases and repos should be here
  final EventStore eventStore;
  final RuntimeRepo runtimeRepo;
  final Logger logger;

  final IdGenerator idGenerator;
  final TimeProvider timeProvider;

  /// Size for the pagination of event store queries, usually leave to defaults
  /// This is an awkward parameter tbh... Maybe its defined by the runtime rather then
  /// the runtime user?
  final int eventStorePageSize;

  const CqrsRuntimeConfig({
    required this.eventStore,
    required this.runtimeRepo,
    required this.logger,
    required this.idGenerator,
    required this.timeProvider,
    this.eventStorePageSize = 20,
  });
}
