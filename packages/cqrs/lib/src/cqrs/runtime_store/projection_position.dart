sealed class ProjectionPosition {
  const ProjectionPosition();
}

final class ProjectionNotInitialized extends ProjectionPosition {
  const ProjectionNotInitialized();
}

final class ProjectionInconsistent extends ProjectionPosition {
  const ProjectionInconsistent();
}

final class ProjectionAtSequence extends ProjectionPosition {
  final int sequence;

  ProjectionAtSequence(int sequence) : sequence = _validate(sequence);

  static int _validate(int sequence) {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence');
    }
    return sequence;
  }
}
