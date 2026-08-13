import 'package:cqrs/cqrs.dart';

class UpsertInput {
  final String noteId;
  final String value;
  // this is the meta of when action was emitted. the repo uses it as a createdAt for insert, and updatedAt for update
  final DateTime timestamp;

  UpsertInput({
    required this.noteId,
    required this.value,
    required this.timestamp,
  });
}

abstract interface class SearchProjectionRepo {
  Future<void> reset();

  Future<ProjectionCheckpoint> checkpoint();

  Future<void> upsertTitle(UpsertInput input, int localSequence);
  Future<void> upsertContent(UpsertInput input, int localSequence);
  Future<void> permanentlyDelete(String noteId, int localSequence);
}
