import 'package:core/cqrs.dart';

abstract interface class SearchProjectionRepo {
  Future<void> reset();

  Future<ProjectionCheckpoint> checkpoint();

  Future<void> upsertTitle(String noteId, String value, int localSequence);
  Future<void> upsertContent(String noteId, String value, int localSequence);
  Future<void> permanentlyDelete(String noteId, int localSequence);
}
