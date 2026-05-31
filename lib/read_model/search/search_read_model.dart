abstract interface class SearchReadModel {
  /// [query] returns ranked noteIds
  /// Currently no filtering is done, all suitable note ids are returned,
  /// without consideration to its trash (or any other filter) status.
  Future<List<String>> query(String query);
}
