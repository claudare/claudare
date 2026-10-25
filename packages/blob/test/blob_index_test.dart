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

      for (final status in [BlobStatus.pending, BlobStatus.available]) {
        test('indexes $status metadata', () async {
          await index.upsert(BlobMetadata(blobId: 'blob', status: status));

          final metadata = await index.get('blob');
          expect(metadata.blobId, 'blob');
          expect(metadata.status, status);
        });
      }

      test('replaces existing metadata', () async {
        await index.upsert(
          const BlobMetadata(blobId: 'blob', status: BlobStatus.pending),
        );

        await index.upsert(
          const BlobMetadata(blobId: 'blob', status: BlobStatus.available),
        );

        expect((await index.get('blob')).status, BlobStatus.available);
      });

      test('indexes blob IDs independently', () async {
        await index.upsert(
          const BlobMetadata(blobId: 'first', status: BlobStatus.pending),
        );
        await index.upsert(
          const BlobMetadata(blobId: 'second', status: BlobStatus.available),
        );

        expect((await index.get('first')).status, BlobStatus.pending);
        expect((await index.get('second')).status, BlobStatus.available);
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
