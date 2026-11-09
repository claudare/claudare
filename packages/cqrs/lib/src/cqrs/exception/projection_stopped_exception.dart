/// A projection stopped before reaching its initial replay target.
class ProjectionStoppedException implements Exception {
  const ProjectionStoppedException();

  @override
  String toString() =>
      'ProjectionStoppedException: projection stopped before catching up';
}
