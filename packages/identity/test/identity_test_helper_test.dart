import 'package:claudare_crypto/crypto.dart';
import 'package:identity/identity.dart';
import 'package:test/test.dart';

void main() {
  test('memory helper returns a migrated store', () async {
    final store = await IdentityTestHelper.createMemoryActorIdentityStore();
    addTearDown(store.close);

    expect(await store.getLocal(), isNull);
    expect(await store.allPeers(), isEmpty);
  });

  test('memory helper creates independent databases', () async {
    final first = await IdentityTestHelper.createMemoryActorIdentityStore();
    addTearDown(first.close);
    final second = await IdentityTestHelper.createMemoryActorIdentityStore();
    addTearDown(second.close);
    await first.setLocal(
      LocalActorIdentity(publicKey: PublicKey.staticValue(1)),
    );

    expect(await second.getLocal(), isNull);
  });

  test('closing a helper store closes its database', () async {
    final store = await IdentityTestHelper.createMemoryActorIdentityStore();

    await store.close();

    await expectLater(store.getLocal(), throwsStateError);
  });
}
