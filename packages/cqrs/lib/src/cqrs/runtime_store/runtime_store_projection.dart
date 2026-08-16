import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';

abstract interface class RuntimeStoreProjection {
  Future<ProjectionPosition> getProjectionPosition(String name);

  Future<void> advanceProjection(
    String name,
    int currentSequence,
    int targetSequence,
    Future<void> Function() action,
  );

  Future<void> resetProjection(String name, Future<void> Function() action);
}
