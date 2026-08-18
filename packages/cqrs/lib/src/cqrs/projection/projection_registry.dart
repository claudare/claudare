import 'package:cqrs/src/cqrs/cqrs_runtime/projection_page_adapter.dart';
import 'package:cqrs/src/cqrs/projection/projection.dart';
import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store_projection.dart';

final class ProjectionRegistry {
  final Set<String> _names = {};
  final List<Projection> _projections = [];

  void add(Projection projection) {
    final name = projection.name;
    if (name.trim().isEmpty) {
      throw const ProjectionConfigurationException(
        'Projection name must not be empty',
      );
    }
    if (name != name.trim()) {
      throw ProjectionConfigurationException(
        'Projection name $name must not have surrounding whitespace',
      );
    }
    if (projection.version <= 0) {
      throw ProjectionConfigurationException(
        'Projection $name must have a positive version',
      );
    }
    // this is technically not needed
    if (projection.streamRoute.pattern.trim().isEmpty) {
      throw ProjectionConfigurationException(
        'Projection $name has an empty stream route pattern',
      );
    }
    if (!_names.add(name)) {
      throw ProjectionConfigurationException(
        'Projection name $name is registered more than once',
      );
    }

    _projections.add(projection);
  }

  /// Temporary bridge for the legacy runtime.
  ///
  /// Stage 7 must remove this getter when `CqrsRuntime` switches to [prepare].
  List<Projection> get projections => List.unmodifiable(_projections);

  Future<List<PreparedProjectionPageAdapter>> prepare(
    RuntimeStoreProjection runtimeStore, {
    required bool forceReset,
  }) {
    return Future.wait(
      _projections.map((projection) async {
        final storedPosition = await runtimeStore.getProjectionPosition(
          projection.name,
        );
        var position = 0;
        var shouldReset = true;
        switch (storedPosition) {
          case ProjectionAtSequence(
            :final version,
            :final scannedThroughLocalSequence,
          ):
            if (!forceReset && version == projection.version) {
              position = scannedThroughLocalSequence;
              shouldReset = false;
            }
          case ProjectionNotInitialized() || ProjectionInconsistent():
            break;
        }
        if (shouldReset) {
          await runtimeStore.resetProjection(
            projection.name,
            projection.version,
            projection.reset,
          );
        }

        return ProjectionPageAdapter(
          projection: projection,
          position: position,
          runtimeStore: runtimeStore,
        );
      }),
    );
  }
}
