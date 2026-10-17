import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final bytes in <List<int>>[
    [],
    [0, 42, 255],
  ]) {
    test('reads stored bytes $bytes', () async {
      final store = MemoryBlobStore();
      await store.save('blob', Uint8List.fromList(bytes));
      final runtime = CqrsTestRuntime(blobStore: store);

      expect(await runtime.getBlob('blob'), bytes);
    });
  }

  test('returns null for an absent blob', () async {
    final runtime = CqrsTestRuntime(blobStore: MemoryBlobStore());

    expect(await runtime.getBlob('missing'), isNull);
  });

  test('propagates storage failures unchanged', () async {
    final failure = Exception('blob read failed');
    final runtime = CqrsTestRuntime(blobStore: _FailingBlobStore(failure));

    await expectLater(runtime.getBlob('blob'), throwsA(same(failure)));
  });
}

class _FailingBlobStore extends MemoryBlobStore {
  final Exception failure;

  _FailingBlobStore(this.failure);

  @override
  Future<Uint8List?> get(String blobId) async => throw failure;
}
