import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_database.dart';
import 'package:time_provider/time_provider.dart';

/// Dependencies used to construct one CQRS runtime.
class CqrsRuntimeDependencies {
  final EventDatabase eventDatabase;
  final RuntimeDatabase runtimeDatabase;
  final Logger logger;

  final TimeProvider timeProvider;

  const CqrsRuntimeDependencies({
    required this.eventDatabase,
    required this.runtimeDatabase,
    required this.logger,
    required this.timeProvider,
  });
}
