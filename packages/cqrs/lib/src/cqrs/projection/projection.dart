import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

abstract interface class Projection<TEvent extends Object, TParams> {
  String get name;
  int get version;
  StreamRoute<TParams> get streamRoute;
  Future<void> reset();

  Future<void> apply(
    TParams streamParams,
    TEvent event,
    EventMetadata metadata,
  );

  void onBatchApplied();
}

final class ProjectionConfigurationException implements Exception {
  final String message;

  const ProjectionConfigurationException(this.message);

  @override
  String toString() => 'ProjectionConfigurationException: $message';
}
