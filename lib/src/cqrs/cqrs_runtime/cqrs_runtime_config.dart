import 'package:core/src/id_generator/id_generator.dart';
import 'package:core/src/time_provider/time_provider.dart';

class CqrsRuntimeConfig {
  final IdGenerator idGenerator;
  final TimeProvider timeProvider;

  /// size for the pagination of event store queries, usually leave to defaults
  final int eventStorePageSize;

  const CqrsRuntimeConfig({
    required this.idGenerator,
    required this.timeProvider,
    this.eventStorePageSize = 20,
  });
}
