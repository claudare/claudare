class PaginatedResult<T> {
  final List<T> data;
  final int? next;

  const PaginatedResult({required this.data, required this.next});
}

typedef ReadPage<T> = Future<PaginatedResult<T>> Function(int cursor);

class PaginatedReader<T> {
  final ReadPage<T> _readPage;

  List<T> _currentPage = const [];
  int? _cursor;

  PaginatedReader(ReadPage<T> readPage, {int initialCursor = 0})
    : _readPage = readPage,
      _cursor = initialCursor;

  List<T> get currentPage => _currentPage;

  Stream<T> scan() async* {
    while (await loadMore()) {
      for (final value in _currentPage) {
        yield value;
      }
    }
  }

  /// Loads the next page and reports whether it contains values.
  ///
  /// Usage example:
  /// ```dart
  /// while (await reader.loadMore()) {
  ///   for (final value in reader.currentPage) {
  ///     // use value
  ///   }
  /// }
  /// ```
  Future<bool> loadMore() async {
    final cursor = _cursor;
    if (cursor == null) return false;

    final result = await _readPage(cursor);
    _currentPage = result.data;
    _cursor = result.next;
    return _currentPage.isNotEmpty;
  }
}
