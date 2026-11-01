import 'dart:io';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in _backends) {
    group(backend.name, () {
      late _StorageSession session;
      late BlobStore storage;

      setUp(() async {
        session = await backend.open();
        storage = session.storage;
      });
      tearDown(() => session.close());

      test('returns null for an absent blob', () async {
        expect(await storage.get('absent'), isNull);
      });

      test('broadcasts newly readable blobs to all listeners', () async {
        final first = storage.availableBlobs.first;
        final second = storage.availableBlobs.first;
        await storage.save('new', Uint8List.fromList([1]));
        expect(await first, 'new');
        expect(await second, 'new');
        expect(await storage.get('new'), [1]);
      });

      test(
        'does not replay availability or announce identical saves',
        () async {
          await storage.save('old', Uint8List.fromList([1]));
          final ids = <String>[];
          final subscription = storage.availableBlobs.listen(ids.add);
          addTearDown(subscription.cancel);
          await storage.save('old', Uint8List.fromList([1]));
          await Future<void>.delayed(Duration.zero);
          expect(ids, isEmpty);
        },
      );

      test('failed saves do not announce availability', () async {
        await storage.save('old', Uint8List.fromList([1]));
        final ids = <String>[];
        final subscription = storage.availableBlobs.listen(ids.add);
        addTearDown(subscription.cancel);
        await expectLater(storage.save('old', Uint8List(0)), throwsStateError);
        await Future<void>.delayed(Duration.zero);
        expect(ids, isEmpty);
      });

      test('lists stored blob IDs', () async {
        expect(await storage.listIds(), isEmpty);
        await storage.save('first', Uint8List.fromList([1]));
        await storage.save('second', Uint8List.fromList([2]));

        expect(await storage.listIds(), unorderedEquals(['first', 'second']));
      });

      test('deletes a blob without affecting other blobs', () async {
        await storage.save('first', Uint8List.fromList([1]));
        await storage.save('second', Uint8List.fromList([2]));

        await storage.delete('first');

        expect(await storage.get('first'), isNull);
        expect(await storage.get('second'), [2]);
        expect(await storage.listIds(), ['second']);
      });

      test('deleting an absent blob succeeds', () async {
        await storage.delete('absent');
        expect(await storage.listIds(), isEmpty);
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
    return _StorageSession(MemoryBlobStore(), () async {});
  }),
  _StorageBackend('file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'file_blob_storage_',
    );
    return _StorageSession(
      FileBlobStore(directory),
      () => directory.delete(recursive: true),
    );
  }),
];

final class _StorageBackend {
  final String name;
  final Future<_StorageSession> Function() open;

  const _StorageBackend(this.name, this.open);
}

final class _StorageSession {
  final BlobStore storage;
  final Future<void> Function() close;

  const _StorageSession(this.storage, this.close);
}
