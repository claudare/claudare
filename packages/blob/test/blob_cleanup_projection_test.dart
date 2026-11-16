import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_cleanup_projection.dart';
import 'package:blob/src/blob_event.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  late MemoryBlobStore store;
  late ProjectionTester<Object, BlobEvent> tester;
  final occuredAt = DateTime.utc(2026);

  setUp(() async {
    store = MemoryBlobStore();
    await store.save('id', Uint8List.fromList([1]));
    tester = ProjectionTester(BlobCleanupProjection(store));
  });

  test('deletes stored bytes for a deleted blob stream', () async {
    await tester.withStreamDeleted('_blob/id', occuredAt: occuredAt).run();
    expect(await store.get('id'), isNull);
  });

  test('preserves bytes for active blobs', () async {
    await tester
        .withEvent('_blob/id', const BlobCreated(), occuredAt: occuredAt)
        .run();
    expect(await store.get('id'), [1]);
  });

  test('preserves bytes without a blob event', () async {
    await tester.run();
    expect(await store.get('id'), [1]);
  });

  test('ignores deletions outside blob streams', () async {
    await tester.withStreamDeleted('other/id', occuredAt: occuredAt).run();
    expect(await store.get('id'), [1]);
  });

  test('propagates storage deletion failures', () async {
    final failing = _FailingStore();
    final result = ProjectionTester(BlobCleanupProjection(failing))
        .withStreamDeleted('_blob/id', occuredAt: occuredAt)
        .run();
    await expectLater(result, throwsA(same(failing.failure)));
  });
}

final class _FailingStore extends MemoryBlobStore {
  final failure = Exception('delete failed');
  @override
  Future<void> delete(String id) async => throw failure;
}
