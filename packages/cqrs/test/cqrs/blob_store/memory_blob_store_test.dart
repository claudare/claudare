import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  late MemoryBlobStore store;
  setUp(() => store = MemoryBlobStore());

  test('returns null for an absent blob', () async {
    expect(await store.get('absent'), isNull);
  });

  for (final bytes in <List<int>>[
    [],
    [0, 255, 42],
  ]) {
    test('stores bytes $bytes', () async {
      await store.save('blob', Uint8List.fromList(bytes));
      expect(await store.get('blob'), bytes);
    });

    test('accepts identical retries for $bytes', () async {
      await store.save('blob', Uint8List.fromList(bytes));
      await store.save('blob', Uint8List.fromList(bytes));
      expect(await store.get('blob'), bytes);
    });
  }

  for (final conflicting in <List<int>>[
    [],
    [2],
    [1, 2],
  ]) {
    test('rejects conflicting bytes $conflicting', () async {
      await store.save('blob', Uint8List.fromList([1]));
      await expectLater(
        store.save('blob', Uint8List.fromList(conflicting)),
        throwsStateError,
      );
      expect(await store.get('blob'), [1]);
    });
  }

  test('copies input bytes', () async {
    final data = Uint8List.fromList([1]);
    await store.save('blob', data);
    data[0] = 2;
    expect(await store.get('blob'), [1]);
  });

  test('copies returned bytes', () async {
    await store.save('blob', Uint8List.fromList([1]));
    (await store.get('blob'))![0] = 2;
    expect(await store.get('blob'), [1]);
  });
}
