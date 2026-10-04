import 'package:claudare_crypto/crypto.dart';
import 'package:cqrs/cqrs.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_system.dart';
import 'package:sync/sync.dart';

class TestIdentities extends MemoryActorIdentityStore {
  Exception? saveError;
  Future<void>? saveDelay;

  @override
  Future<LocalActorIdentity> setLocal(LocalActorIdentity identity) async {
    await saveDelay;
    if (saveError != null) throw saveError!;
    return super.setLocal(identity);
  }
}

class TestKv extends MemoryKv {
  Exception? saveError;
  Future<void>? saveDelay;

  @override
  Future<void> setString(String key, String value) async {
    await saveDelay;
    if (saveError != null) throw saveError!;
    await super.setString(key, value);
  }

  @override
  Future<void> setAllStrings(Map<String, String> entries) async {
    await saveDelay;
    if (saveError != null) throw saveError!;
    await super.setAllStrings(entries);
  }
}

Future<NoteSystem> testSystem({
  bool actor = true,
  bool server = true,
  bool group = true,
}) async {
  final kv = MemoryKv();
  if (server) {
    await kv.setString(NoteSystem.serverUrlKey, 'ws://localhost:7000');
  }
  if (group) await kv.setString(NoteSystem.groupKey, '0');
  final identities = MemoryActorIdentityStore();
  if (actor) {
    await identities.setLocal(
      LocalActorIdentity(publicKey: PublicKey.staticValue(42)),
    );
  }
  return NoteSystem(
    identities: identities,
    kv: kv,
    eventStore: MemoryEventStore(),
  );
}
