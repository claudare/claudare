import 'fts.dart';

/// Blank fts for testing. It does not do anything
class NoopFts implements Fts {
  @override
  Future<void> delete(String id, int revision) async => {};

  @override
  Future<int?> getRevision() async => -1;

  @override
  Future<List<String>> query(String query, int resultCount) async => [];

  @override
  Future<void> upsert(String id, String content, int revision) async => {};
}
