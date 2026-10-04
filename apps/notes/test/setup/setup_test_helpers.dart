import 'package:claudare_crypto/crypto.dart';
import 'package:cqrs/cqrs.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_system.dart';
import 'package:sync/sync.dart';

class TestIdentities implements ActorIdentityStore {
  LocalActorIdentity? local;
  Exception? saveError;
  Future<void>? saveDelay;

  TestIdentities({this.local});

  @override
  Future<LocalActorIdentity?> getLocal() async => local;

  @override
  Future<LocalActorIdentity> setLocal(LocalActorIdentity identity) async {
    await saveDelay;
    if (saveError != null) throw saveError!;
    return local = identity;
  }

  @override
  Future<List<PeerActorIdentity>> allPeers() async => [];

  @override
  Future<PeerActorIdentity?> getPeer(PublicKey publicKey) async => null;

  @override
  Future<void> addPeer(PeerActorIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<void> deleteAllPeers() => throw UnimplementedError();
}

class TestKv implements Kv {
  final values = <String, String>{};
  Exception? saveError;
  Future<void>? saveDelay;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    await saveDelay;
    if (saveError != null) throw saveError!;
    values[key] = value;
  }

  @override
  Future<void> setAll(List<KeyValue> entries) => throw UnimplementedError();

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<KeyValue>> list(String prefix) => throw UnimplementedError();
}

NoteSystem testSystem({bool actor = true, bool server = true}) {
  final kv = TestKv();
  if (server) kv.values[NoteSystem.serverUrlKey] = 'ws://localhost:7000';
  return NoteSystem(
    identities: TestIdentities(
      local: actor
          ? LocalActorIdentity(publicKey: PublicKey.staticValue(42))
          : null,
    ),
    kv: kv,
    eventStore: MemoryEventStore(),
  );
}
