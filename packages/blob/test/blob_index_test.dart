import 'package:blob/blob.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in _backends) {
    group(backend.name, () {
      late _IndexSession session;
      late BlobIndex index;

      setUp(() async {
        session = await backend.open();
        index = session.index;
      });
      tearDown(() => session.close());

      test('returns missing metadata for an unknown blob', () async {
        final metadata = await index.get('unknown');

        expect(metadata.blobId, 'unknown');
        expect(metadata.status, BlobStatus.missing);
      });

      test('marks a blob available', () async {
        await index.markAvailable('blob');

        final metadata = await index.get('blob');
        expect(metadata.blobId, 'blob');
        expect(metadata.status, BlobStatus.available);
      });

      test('marks the same blob available multiple times', () async {
        await index.markAvailable('blob');
        await index.markAvailable('blob');

        final metadata = await index.get('blob');
        expect(metadata.blobId, 'blob');
        expect(metadata.status, BlobStatus.available);
      });

      test('indexes blob IDs independently', () async {
        await index.markAvailable('first');

        expect((await index.get('first')).status, BlobStatus.available);
        expect((await index.get('second')).status, BlobStatus.missing);
      });
    });
  }
}

final _backends = <_IndexBackend>[
  _IndexBackend('memory', () async {
    return _IndexSession(MemoryBlobIndex(), () async {});
  }),
  _IndexBackend('sqlite', () async {
    final database = IsolateSqlite();
    await database.openInMemory();
    try {
      final index = SqliteBlobIndex(database);
      await index.migrate();
      return _IndexSession(index, database.close);
    } catch (_) {
      await database.close();
      rethrow;
    }
  }),
];

final class _IndexBackend {
  final String name;
  final Future<_IndexSession> Function() open;

  const _IndexBackend(this.name, this.open);
}

final class _IndexSession {
  final BlobIndex index;
  final Future<void> Function() close;

  const _IndexSession(this.index, this.close);
}
