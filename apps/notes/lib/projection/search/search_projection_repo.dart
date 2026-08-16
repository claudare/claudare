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

  Future<void> upsertTitle(UpsertInput input);
  Future<void> upsertContent(UpsertInput input);
  Future<void> permanentlyDelete(String noteId);
}
