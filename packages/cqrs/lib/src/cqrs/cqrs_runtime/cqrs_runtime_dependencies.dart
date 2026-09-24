import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/event_store/event_database.dart';
import 'package:time_provider/time_provider.dart';

/// Dependencies used to construct one CQRS runtime.
class CqrsRuntimeDependencies {
  final EventDatabase eventDatabase;
  final Logger logger;

  final TimeProvider timeProvider;

  const CqrsRuntimeDependencies({
    required this.eventDatabase,
    required this.logger,
    required this.timeProvider,
  });
}
