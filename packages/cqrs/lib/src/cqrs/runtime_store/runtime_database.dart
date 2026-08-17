import 'package:cqrs/src/cqrs/runtime_store/projection_position.dart';

abstract interface class RuntimeDatabase {
  Future<void> initialize();

  Future<RuntimeProjectionState?> getProjectionState(String name);
  Future<void> setProjectionState(String name, RuntimeProjectionState state);
}

/// Durable version and page progress for one projection.
///
/// A consistent state has a positive [version] and equal, non-negative
/// applying and scanned-through boundaries. A missing or unequal boundary
/// represents incomplete work and requires the projection to reset.
final class RuntimeProjectionState {
  /// The positive projection model version targeted by this state.
  ///
  /// Reset stores the target version before rebuilding the projection. This
  /// value therefore identifies the schema being attempted, not whether the
  /// reset completed.
  final int version;

  /// The receiver-local sequence through which the current action is applying.
  ///
  /// It is the target page boundary during replay. When it equals
  /// [scannedThroughLocalSequence], the action through this boundary completed.
  final int? applyingThroughLocalSequence;

  /// The last receiver-local sequence the projection fully considered.
  ///
  /// This includes unrelated events that did not match the projection route.
  /// A null value means reset has not completed. A non-null value different
  /// from [applyingThroughLocalSequence] means an action was interrupted.
  final int? scannedThroughLocalSequence;

  const RuntimeProjectionState({
    required this.version,
    required this.applyingThroughLocalSequence,
    required this.scannedThroughLocalSequence,
  });

  /// The usable projection position represented by this durable state.
  ///
  /// Invalid versions and incomplete or interrupted boundaries are reported as
  /// inconsistent so the projection resets before replay.
  ProjectionPosition get projectionPosition {
    final applying = applyingThroughLocalSequence;
    final scanned = scannedThroughLocalSequence;
    if (applying == null ||
        scanned == null ||
        applying != scanned ||
        version <= 0 ||
        applying < 0) {
      return const ProjectionInconsistent();
    }
    return ProjectionAtSequence(
      version: version,
      scannedThroughLocalSequence: scanned,
    );
  }
}
