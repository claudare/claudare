import 'fts.dart';

/// Stores documents in memory and ranks case-insensitive word prefix matches.
class MemoryFts implements Fts {
  final _index = <String, List<String>>{};
  int? _revision;

  @override
  Future<void> delete(String id, int revision) async {
    _index.remove(id);
    _revision = revision;
  }

  @override
  Future<int?> getRevision() async => _revision;

  @override
  Future<List<String>> query(String query, int resultCount) async {
    final words = _words(query);
    final hits = <String, int>{};
    for (final entry in _index.entries) {
      var count = 0;
      for (final word in entry.value) {
        for (final prefix in words) {
          if (word.startsWith(prefix)) {
            count++;
          }
        }
      }
      if (count > 0) {
        hits[entry.key] = count;
      }
    }
    final ids = hits.keys.toList()
      ..sort((a, b) => hits[b]!.compareTo(hits[a]!));
    return ids.take(resultCount).toList();
  }

  @override
  Future<void> upsert(String id, String content, int revision) async {
    _index[id] = _words(content);
    _revision = revision;
  }
}

List<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList();
