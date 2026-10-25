import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in _backends) {
    group(backend.name, () {
      late _StorageSession session;
      late BlobStorage storage;

      setUp(() async {
        session = await backend.open();
        storage = session.storage;
      });
      tearDown(() => session.close());

      test('returns null for an absent blob', () async {
        expect(await storage.get('absent'), isNull);
      });

      for (final bytes in <List<int>>[
        [],
        [0, 255, 42],
      ]) {
        test('stores bytes $bytes', () async {
          await storage.save('blob', Uint8List.fromList(bytes));

          expect(await storage.get('blob'), bytes);
        });

        test('accepts identical retries for $bytes', () async {
          await storage.save('blob', Uint8List.fromList(bytes));
          await storage.save('blob', Uint8List.fromList(bytes));

          expect(await storage.get('blob'), bytes);
        });
      }

      for (final conflicting in <List<int>>[
        [],
        [2],
        [1, 2],
      ]) {
        test('rejects conflicting bytes $conflicting', () async {
          await storage.save('blob', Uint8List.fromList([1]));

          await expectLater(
            storage.save('blob', Uint8List.fromList(conflicting)),
            throwsStateError,
          );
          expect(await storage.get('blob'), [1]);
        });
      }

      test('copies input bytes', () async {
        final data = Uint8List.fromList([1]);
        await storage.save('blob', data);
        data[0] = 2;

        expect(await storage.get('blob'), [1]);
      });

      test('copies returned bytes', () async {
        await storage.save('blob', Uint8List.fromList([1]));
        (await storage.get('blob'))![0] = 2;

        expect(await storage.get('blob'), [1]);
      });

      test('stores independent blob IDs', () async {
        await storage.save('first', Uint8List.fromList([1]));
        await storage.save('second', Uint8List.fromList([2]));

        expect(await storage.get('first'), [1]);
        expect(await storage.get('second'), [2]);
      });
    });
  }
}

final _backends = <_StorageBackend>[
  _StorageBackend('memory', () async {
    return _StorageSession(MemoryBlobStorage(), () async {});
  }),
  _StorageBackend('sqlite', () async {
    final database = IsolateSqlite();
    await database.openInMemory();
    try {
      final storage = SqliteBlobStorage(database);
      await storage.migrate();
      return _StorageSession(storage, database.close);
    } catch (_) {
      await database.close();
      rethrow;
    }
  }),
];

final class _StorageBackend {
  final String name;
  final Future<_StorageSession> Function() open;

  const _StorageBackend(this.name, this.open);
}

final class _StorageSession {
  final BlobStorage storage;
  final Future<void> Function() close;

  const _StorageSession(this.storage, this.close);
}
