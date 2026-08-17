import 'package:cqrs/src/cqrs/exception/runtime_store_exception.dart';

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
  final int version;
  final int scannedThroughLocalSequence;

  ProjectionAtSequence({
    required int version,
    required int scannedThroughLocalSequence,
  }) : version = _validateVersion(version),
       scannedThroughLocalSequence = _validateSequence(
         scannedThroughLocalSequence,
       );

  static int _validateVersion(int version) {
    if (version <= 0) {
      throw RuntimeStoreException(
        'Projection version must be positive: $version',
      );
    }
    return version;
  }

  static int _validateSequence(int sequence) {
    if (sequence < 0) {
      throw RuntimeStoreException(
        'Scanned-through local sequence must not be negative: $sequence',
      );
    }
    return sequence;
  }
}
