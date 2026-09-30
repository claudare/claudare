import 'package:cqrs/cqrs.dart';
import 'package:kv/kv.dart';
import 'package:sync/sync.dart';

/// Notes, settings, and actor identities stored in one database.
class NoteSystem {
  static const serverUrlKey = 'sync.serverUrl';

  final ActorIdentityStore identities;
  final Kv kv;
  final EventStore eventStore;

  const NoteSystem({
    required this.identities,
    required this.kv,
    required this.eventStore,
  });
}
