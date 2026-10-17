import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

/// Opens an independent blob store for behavioral tests.
abstract interface class BlobStoreTestBackend {
  String get name;
  Future<BlobStoreTestSession> open();
}

/// A ready-to-use blob store and its resource lifetime.
abstract interface class BlobStoreTestSession {
  BlobStore get store;
  Future<void> close();
}

/// Creates in-memory reference stores for blob tests.
class MemoryBlobStoreTestBackend implements BlobStoreTestBackend {
  const MemoryBlobStoreTestBackend();

  @override
  String get name => 'memory';

  @override
  Future<BlobStoreTestSession> open() async =>
      _MemoryBlobStoreTestSession(MemoryBlobStore());
}

/// Creates migrated SQLite stores in independent in-memory databases.
class SqliteBlobStoreTestBackend implements BlobStoreTestBackend {
  const SqliteBlobStoreTestBackend();

  @override
  String get name => 'sqlite';

  @override
  Future<BlobStoreTestSession> open() async {
    final sqlite = IsolateSqlite();
    await sqlite.openInMemory();
    try {
      final store = SqliteBlobStore(sqlite);
      await store.migrate();
      return _SqliteBlobStoreTestSession(store);
    } catch (_) {
      await sqlite.close();
      rethrow;
    }
  }
}

/// Storage backends that implement the same blob contract.
const blobStoreTestBackends = <BlobStoreTestBackend>[
  MemoryBlobStoreTestBackend(),
  SqliteBlobStoreTestBackend(),
];

class _MemoryBlobStoreTestSession implements BlobStoreTestSession {
  @override
  final MemoryBlobStore store;
  _MemoryBlobStoreTestSession(this.store);

  @override
  Future<void> close() async {}
}

class _SqliteBlobStoreTestSession implements BlobStoreTestSession {
  @override
  final SqliteBlobStore store;
  Future<void>? _closeFuture;
  _SqliteBlobStoreTestSession(this.store);

  @override
  Future<void> close() => _closeFuture ??= store.close();
}
