class ProjectionCheckpoint {
  final int localSequence;

  const ProjectionCheckpoint({required this.localSequence});

  ProjectionCheckpoint.zero() : localSequence = 0;

  bool get isZero => localSequence == 0;
}
