import 'package:kv/kv.dart';
import 'package:test/test.dart';

void main() {
  test('memory helper returns a migrated store', () async {
    final store = await KvTestHelper.createMemoryKv();
    addTearDown(store.close);

    expect(await store.list(''), isEmpty);
  });

  test('memory helper creates independent databases', () async {
    final first = await KvTestHelper.createMemoryKv();
    addTearDown(first.close);
    final second = await KvTestHelper.createMemoryKv();
    addTearDown(second.close);
    await first.set('a', 'one');

    expect(await second.get('a'), isNull);
  });

  test('closing a helper store closes its database', () async {
    final store = await KvTestHelper.createMemoryKv();

    await store.close();

    await expectLater(store.get('a'), throwsStateError);
  });
}
