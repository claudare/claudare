class ProjectionCheckpoint {
  final int localSequence;
  final int localVersion; // FIXME: remove

  const ProjectionCheckpoint({
    required this.localSequence,
    required this.localVersion,
  });

  ProjectionCheckpoint.zero() : localSequence = 0, localVersion = 0;

  get isZero => localSequence == 0 && localVersion == 0;
}
