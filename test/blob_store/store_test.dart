import 'dart:async';
import 'dart:io';
import 'package:core/blob_store.dart';
import 'package:test/test.dart';

void main() {
  group('BlobStore', () {
    late BlobStore blobStore;

    setUp(() async {
      blobStore = BlobStore.temporary();
      await blobStore.init();
    });

    tearDown(() async {
      await blobStore.deinit();
    });

    test('should write and read a blob', () async {
      final id = BlobId('test_blob');
      final data = Stream.fromIterable([
        [1, 2, 3],
      ]);
      await blobStore.write(id, data);

      expect(await blobStore.has(id), isTrue);

      var stream = blobStore.read(id);
      List<int> result = [];
      await for (var chunk in stream) {
        result.addAll(chunk);
      }
      expect(result, equals([1, 2, 3]));
    });

    test('should delete a blob', () async {
      final id = BlobId('delete_test_blob');
      final data = Stream.fromIterable([
        [1, 2, 3],
      ]);
      await blobStore.write(id, data);

      expect(await blobStore.has(id), isTrue);
      expect(await blobStore.delete(id), isTrue);
      expect(await blobStore.has(id), isFalse);
    });

    test('should get stats for a blob', () async {
      final id = BlobId('stat_test_blob');
      final data = Stream.fromIterable([
        [1, 2, 3],
      ]);
      await blobStore.write(id, data);

      expect(await blobStore.has(id), isTrue);

      var stat = await blobStore.stat(id);
      expect(stat, isNotNull);
      expect(stat!.ciphertextLengthBytes, equals(3));
    });

    test('should get blob list', () async {
      final id = BlobId('list_test_blob');
      final data = Stream<List<int>>.fromIterable([
        [1, 2, 3],
      ]);
      await blobStore.write(id, data);

      expect(await blobStore.has(id), isTrue);

      var list = await blobStore.list().toList();
      expect(list.length, 1);
      expect(list[0], id);
    });

    test('should handle non-existent blob stats', () async {
      final id = BlobId('non_existent_test_blob');
      var stat = await blobStore.stat(id);
      expect(stat, isNull);
    });

    test('should throw on non-existent blob read', () async {
      final id = BlobId('non_existent_test_blob');
      var stream = blobStore.read(id);
      expect(() => stream.first, throwsA(isA<PathNotFoundException>()));
    });

    test('should not allow overwrite', () async {
      final id = BlobId('stat_test_blob');
      final data = Stream.fromIterable([
        [1, 2, 3],
      ]);
      await blobStore.write(id, data);

      expect(await blobStore.has(id), isTrue);

      final data2 = Stream.fromIterable([
        [4, 5, 6],
      ]);
      expect(() => blobStore.write(id, data2), throwsException);
    });
  });
}
