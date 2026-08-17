import 'projection_failure_handler.dart';
import 'projection_route.dart';

abstract interface class Projection {
  String get name;
  int get version;
  List<ProjectionRoute> get routes;
  ProjectionFailureHandler get failureHandler;

  Future<void> reset();
  void onBatchApplied();
}

final class ProjectionConfigurationException implements Exception {
  final String message;

  const ProjectionConfigurationException(this.message);

  @override
  String toString() => 'ProjectionConfigurationException: $message';
}
