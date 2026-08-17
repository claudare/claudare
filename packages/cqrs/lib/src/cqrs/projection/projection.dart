import 'package:cqrs/src/cqrs/event/event_metadata.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

import 'projection_failure_handler.dart';

abstract interface class Projection<TEvent extends Object, TParams> {
  String get name;
  int get version;
  StreamRoute<TParams> get streamRoute;
  ProjectionFailureHandler get failureHandler;

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
