import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:test/test.dart';

void main() {
  late MemoryBlobIndex index;
  late MemoryBlobStorage storage;
  late BlobStore store;

  setUp(() {
    index = MemoryBlobIndex();
    storage = MemoryBlobStorage();
    store = BlobStore(index: index, storage: storage);
  });

  test(
    'returns null for a missing blob without reading stored bytes',
    () async {
      final indexedStore = BlobStore(
        index: index,
        storage: _FailingReadBlobStorage(),
      );

      expect(await indexedStore.get('blob'), isNull);
    },
  );

  test('returns bytes for an available blob', () async {
    await storage.save('blob', Uint8List.fromList([1, 2]));
    await index.markAvailable('blob');

    expect(await store.get('blob'), [1, 2]);
  });

  test('rejects available metadata without stored bytes', () async {
    await index.markAvailable('blob');

    await expectLater(store.get('blob'), throwsStateError);
  });

  test('stores bytes before marking the blob available', () async {
    final operations = <String>[];
    final recordingStore = BlobStore(
      index: _RecordingBlobIndex(index, operations),
      storage: _RecordingBlobStorage(storage, operations),
    );

    await recordingStore.save('blob', Uint8List.fromList([1]));

    expect(operations, ['storage.save', 'index.markAvailable']);
    expect(await storage.get('blob'), [1]);
    expect((await index.get('blob')).status, BlobStatus.available);
  });

  test('leaves the index unchanged when storage fails', () async {
    final failingStore = BlobStore(
      index: index,
      storage: _FailingBlobStorage(),
    );

    await expectLater(
      failingStore.save('blob', Uint8List.fromList([1])),
      throwsException,
    );

    expect((await index.get('blob')).status, BlobStatus.missing);
  });

  test('an identical retry completes a failed index update', () async {
    final failingIndex = _FailOnceBlobIndex(index);
    final retryingStore = BlobStore(index: failingIndex, storage: storage);

    await expectLater(
      retryingStore.save('blob', Uint8List.fromList([1])),
      throwsException,
    );
    expect(await storage.get('blob'), [1]);
    expect((await index.get('blob')).status, BlobStatus.missing);

    await retryingStore.save('blob', Uint8List.fromList([1]));

    expect((await index.get('blob')).status, BlobStatus.available);
  });

  test('does not change metadata after a conflicting save', () async {
    await storage.save('blob', Uint8List.fromList([1]));
    await index.markAvailable('blob');

    await expectLater(
      store.save('blob', Uint8List.fromList([2])),
      throwsStateError,
    );

    expect((await index.get('blob')).status, BlobStatus.available);
  });
}

final class _RecordingBlobIndex implements BlobIndex {
  final BlobIndex _index;
  final List<String> _operations;

  const _RecordingBlobIndex(this._index, this._operations);

  @override
  Future<BlobMetadata> get(String blobId) => _index.get(blobId);

  @override
  Future<void> markAvailable(String blobId) {
    _operations.add('index.markAvailable');
    return _index.markAvailable(blobId);
  }
}

final class _RecordingBlobStorage implements BlobStorage {
  final BlobStorage _storage;
  final List<String> _operations;

  const _RecordingBlobStorage(this._storage, this._operations);

  @override
  Future<Uint8List?> get(String blobId) => _storage.get(blobId);

  @override
  Future<void> save(String blobId, Uint8List data) {
    _operations.add('storage.save');
    return _storage.save(blobId, data);
  }
}

final class _FailingBlobStorage implements BlobStorage {
  @override
  Future<Uint8List?> get(String blobId) async => null;

  @override
  Future<void> save(String blobId, Uint8List data) async {
    throw Exception('Storage failed');
  }
}

final class _FailingReadBlobStorage implements BlobStorage {
  @override
  Future<Uint8List?> get(String blobId) async {
    throw Exception('Storage read');
  }

  @override
  Future<void> save(String blobId, Uint8List data) async {}
}

final class _FailOnceBlobIndex implements BlobIndex {
  final BlobIndex _index;
  var _shouldFail = true;

  _FailOnceBlobIndex(this._index);

  @override
  Future<BlobMetadata> get(String blobId) => _index.get(blobId);

  @override
  Future<void> markAvailable(String blobId) {
    if (_shouldFail) {
      _shouldFail = false;
      throw Exception('Index failed');
    }
    return _index.markAvailable(blobId);
  }
}
