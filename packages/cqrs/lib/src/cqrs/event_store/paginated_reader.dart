import 'package:cqrs/src/cqrs/event_store/paginated_read_result.dart';

typedef ReadPage<T> = Future<PaginatedResult<T>> Function(int cursor);

class PaginatedReader<T> {
  final ReadPage<T> _readPage;

  List<T> _currentPage = const [];
  int? _cursor;
  bool _hasScanned = false;

  PaginatedReader(ReadPage<T> readPage, {int initialCursor = 0})
    : _readPage = readPage,
      _cursor = initialCursor;

  Stream<T> scan() async* {
    if (_hasScanned) {
      throw StateError('scan can only be run once');
    }
    _hasScanned = true;

    while (await _loadMore()) {
      for (final event in _currentPage) {
        yield event;
      }
    }
  }

  Future<bool> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null) return false;

    final result = await _readPage(cursor);
    _currentPage = result.data;
    _cursor = result.next;
    return _currentPage.isNotEmpty;
  }
}
