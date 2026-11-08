/// Full-text search interface.
/// Documents are referenced by an id.
/// Revision will be logPosition, in order to support persistent projections.
abstract interface class Fts {
  /// Upserts a record
  Future<void> upsert(String id, String content, int revision);

  /// Deletes a record
  Future<void> delete(String id, int revision);

  /// Returns ids ranked by relevance by text query
  Future<List<String>> query(String query, int resultCount);

  /// Returns last applied revision. Null when no revisions were applied.
  Future<int?> getRevision();
}
