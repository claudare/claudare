/// [ProjectionCheckpoint] represents the checkpoint of a projection,
/// which is the local sequence number of the last event applied.
/// Value of 0 means that the projection is initialized, but nothing was applied yet.
/// Value of nil means that the projection is not initialized, and reset() method will be called.
class ProjectionCheckpoint {
  final int? _localSequence;

  const ProjectionCheckpoint(int localSequence)
    : _localSequence = localSequence;

  ProjectionCheckpoint.zero() : _localSequence = 0;
  ProjectionCheckpoint.notInitialized() : _localSequence = null;

  // zero checkpoint is okay, meaning no events were applied here (it can happen)
  // however, null checkpoint means that this projection was not initialized
  bool get isProjectionInitialized => _localSequence != null;

  int get localSequence => _localSequence ?? 0;
}
