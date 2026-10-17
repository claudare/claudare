import 'dart:typed_data';

import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in blobStoreTestBackends) {
    group(backend.name, () {
      test('opens a ready store', () async {
        final session = await backend.open();
        addTearDown(session.close);
        expect(await session.store.get('absent'), isNull);
        await session.store.save('blob', Uint8List.fromList([1]));
        expect(await session.store.get('blob'), [1]);
      });

      test('opens independent sessions', () async {
        final first = await backend.open();
        addTearDown(first.close);
        final second = await backend.open();
        addTearDown(second.close);
        await first.store.save('blob', Uint8List.fromList([1]));
        expect(await second.store.get('blob'), isNull);
      });
    });
  }

  test('SQLite session closes its database idempotently', () async {
    final session = await const SqliteBlobStoreTestBackend().open();
    addTearDown(session.close);
    final closing = session.close();
    expect(session.close(), same(closing));
    await closing;
    await expectLater(session.store.get('blob'), throwsStateError);
  });
}
