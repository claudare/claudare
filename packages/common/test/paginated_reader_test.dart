import 'package:common/common.dart';
import 'package:test/test.dart';

void main() {
  group('PaginatedReader', () {
    test('scans pages from the initial cursor in order', () async {
      final cursors = <int>[];
      final reader = PaginatedReader<int>((cursor) async {
        cursors.add(cursor);
        return switch (cursor) {
          5 => const PaginatedResult(data: [6, 7], next: 7),
          7 => const PaginatedResult(data: [8], next: null),
          _ => throw StateError('unexpected cursor $cursor'),
        };
      }, initialCursor: 5);

      expect(await reader.scan().toList(), [6, 7, 8]);
      expect(cursors, [5, 7]);
    });

    test('loads pages for manual iteration', () async {
      final reader = PaginatedReader<int>((cursor) async {
        return switch (cursor) {
          0 => const PaginatedResult(data: [1, 2], next: 2),
          2 => const PaginatedResult(data: [3], next: null),
          _ => throw StateError('unexpected cursor $cursor'),
        };
      });
      final values = <int>[];

      while (await reader.loadMore()) {
        values.addAll(reader.currentPage);
      }

      expect(values, [1, 2, 3]);
    });

    test('handles an empty first page', () async {
      final reader = PaginatedReader<int>((cursor) async {
        return const PaginatedResult(data: [], next: null);
      });

      expect(await reader.scan().toList(), isEmpty);
    });

    test('does not throw when scanned again', () async {
      final reader = PaginatedReader<int>((cursor) async {
        return const PaginatedResult(data: [1], next: null);
      });

      expect(await reader.scan().toList(), [1]);
      expect(await reader.scan().toList(), isEmpty);
    });
  });
}
