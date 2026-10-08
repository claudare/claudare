import 'dart:async';
import 'dart:io';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/reset_database.dart';
import 'package:sync/sync.dart';
import 'package:time_provider/time_provider.dart';

import '../sync_test_transport.dart';

void main() {
  for (final initiallyEnabled in [false, true]) {
    test(
      'applying settings creates a fresh configured transport from enabled=$initiallyEnabled',
      () async {
        final transports = <TestTransport>[];
        final configurations = <(String, String, String)>[];
        final bootstrap = _bootstrap(
          TestTransport(),
          createTransport: ({required url, required actor, required group}) {
            configurations.add((url, actor, group));
            final transport = TestTransport();
            transports.add(transport);
            return transport;
          },
        );
        final system = await _system(bootstrap, enabled: initiallyEnabled);
        final app = await bootstrap.initialize(
          system: system,
          actor: _actor(1),
        );
        await app.command.createNote('retained-note');
        final previous = bootstrap.syncCoordinator;
        await system.kv.setAll({
          NoteSystem.syncEnabledKey: true,
          NoteSystem.serverUrlKey: 'wss://replacement.test',
          NoteSystem.groupKey: 'replacement',
        });
        await bootstrap.restartSync();
        expect(configurations.last, (
          'wss://replacement.test',
          _actor(1),
          'replacement',
        ));
        expect(transports.last.starts, 1);
        if (initiallyEnabled) {
          expect(transports.first.closed, isTrue);
          expect(previous!.snapshot.connection, SyncConnectionState.closed);
        }
        expect(await app.query.noteList(), hasLength(1));
      },
    );
  }

  test('applying unchanged settings still replaces the coordinator', () async {
    final transports = <TestTransport>[];
    final bootstrap = _bootstrap(
      TestTransport(),
      createTransport: ({required url, required actor, required group}) {
        final transport = TestTransport();
        transports.add(transport);
        return transport;
      },
    );
    final system = await _system(bootstrap);
    await bootstrap.initialize(system: system, actor: _actor(1));
    final previous = bootstrap.syncCoordinator;
    await bootstrap.restartSync();
    expect(bootstrap.syncCoordinator, isNot(same(previous)));
    expect(transports, hasLength(2));
    expect(transports.first.closed, isTrue);
  });

  test('an older settings reload cannot replace a newer coordinator', () async {
    final kv = _DelayedKv();
    final bootstrap = _bootstrap(
      TestTransport(),
      createTransport: ({required url, required actor, required group}) =>
          TestTransport(),
    );
    final system = await _memorySystem(kv);
    await bootstrap.initialize(system: system, actor: _actor(1));
    final held = kv.gate = Completer<void>();
    final stale = bootstrap.restartSync();
    kv.gate = null;
    await kv.setString(NoteSystem.groupKey, 'newer');
    await bootstrap.restartSync();
    final current = bootstrap.syncCoordinator;
    held.complete();
    await stale;
    expect(bootstrap.syncCoordinator, same(current));
    expect(current!.snapshot.connection, SyncConnectionState.connected);
  });

  test(
    'shutdown prevents a pending settings reload from restarting sync',
    () async {
      final kv = _DelayedKv();
      final transport = TestTransport();
      final bootstrap = _bootstrap(transport);
      final system = await _memorySystem(kv);
      await bootstrap.initialize(system: system, actor: _actor(1));
      final held = kv.gate = Completer<void>();
      final pending = bootstrap.restartSync();
      await bootstrap.close();
      held.complete();
      await pending;
      expect(transport.starts, 1);
      expect(transport.closed, isTrue);
      expect(
        bootstrap.syncCoordinator!.snapshot.connection,
        SyncConnectionState.closed,
      );
    },
  );

  test('failed configuration reads preserve the current transport', () async {
    final kv = _DelayedKv();
    final transport = TestTransport();
    final bootstrap = _bootstrap(transport);
    final system = await _memorySystem(kv);
    await bootstrap.initialize(system: system, actor: _actor(1));
    final previous = bootstrap.syncCoordinator;
    kv.failReads = true;
    await expectLater(bootstrap.restartSync(), throwsA(isA<Exception>()));
    expect(bootstrap.syncCoordinator, same(previous));
    expect(transport.closed, isFalse);
  });

  test(
    'startup permits local editing without waiting for connectivity',
    () async {
      final transport = TestTransport();
      final connecting = Completer<void>();
      transport.onStart = () => connecting.future;
      final bootstrap = _bootstrap(transport);
      final system = await _system(bootstrap);
      final application = await bootstrap.initialize(
        system: system,
        actor: _actor(1),
      );
      expect(transport.starts, 1);
      expect(
        bootstrap.syncCoordinator!.snapshot.connection,
        SyncConnectionState.connecting,
      );
      await application.command.createNote('offline-note');
      expect(await application.query.noteList(), hasLength(1));
      connecting.complete();
    },
  );

  test('repeated initialization starts only one coordinator', () async {
    final transport = TestTransport();
    final bootstrap = _bootstrap(transport);
    final system = await _system(bootstrap);
    final application = await bootstrap.initialize(
      system: system,
      actor: _actor(1),
    );
    final coordinator = bootstrap.syncCoordinator;
    expect(
      await bootstrap.initialize(system: system, actor: _actor(1)),
      same(application),
    );
    expect(bootstrap.syncCoordinator, same(coordinator));
    expect(transport.starts, 1);
  });

  for (final enabled in <bool?>[null, false]) {
    test('sync choice $enabled opens no transport', () async {
      final transport = TestTransport();
      final bootstrap = _bootstrap(transport);
      final system = await _system(bootstrap, enabled: enabled);
      await bootstrap.initialize(system: system, actor: _actor(1));
      expect(transport.starts, 0);
      expect(bootstrap.syncCoordinator, isNull);
      expect(bootstrap.syncUnavailableReason, 'Disabled');
    });
  }

  for (final (url, group) in <(String?, String?)>[
    (null, 'notes'),
    ('invalid', 'notes'),
    ('https://example.test', 'notes'),
    ('ws://', 'notes'),
    ('ws://example.test', null),
    ('ws://example.test', ' '),
  ]) {
    test(
      'incomplete configuration $url / $group permits local Notes',
      () async {
        final transport = TestTransport();
        final bootstrap = _bootstrap(transport);
        final system = await _system(bootstrap, url: url, group: group);
        final application = await bootstrap.initialize(
          system: system,
          actor: _actor(1),
        );
        await application.command.createNote('local-note');
        expect(transport.starts, 0);
        expect(bootstrap.syncCoordinator, isNull);
        expect(bootstrap.syncUnavailableReason, 'Not configured');
      },
    );
  }

  test(
    'connection failure leaves Notes usable while reconnect is scheduled',
    () async {
      final transport = TestTransport()
        ..onStart = () async => throw Exception('offline');
      final bootstrap = _bootstrap(transport);
      final system = await _system(bootstrap);
      final application = await bootstrap.initialize(
        system: system,
        actor: _actor(1),
      );
      await application.command.createNote('local-note');
      expect(
        bootstrap.syncCoordinator!.snapshot.connection,
        SyncConnectionState.reconnecting,
      );
      expect(await application.query.noteList(), hasLength(1));
    },
  );

  test('applying disabled settings stops the running coordinator', () async {
    final transport = TestTransport();
    final bootstrap = _bootstrap(transport);
    final system = await _system(bootstrap);
    await bootstrap.initialize(system: system, actor: _actor(1));
    final coordinator = bootstrap.syncCoordinator;
    await system.kv.setBool(NoteSystem.syncEnabledKey, false);
    await bootstrap.restartSync();
    expect(bootstrap.syncCoordinator, isNull);
    expect(coordinator!.snapshot.connection, SyncConnectionState.closed);
    expect(transport.closed, isTrue);
    expect(transport.starts, 1);
  });

  test('shutdown stops transport before SQLite and is idempotent', () async {
    final order = <String>[];
    final transport = TestTransport()..onClose = () => order.add('transport');
    final sqlite = _ObservedSqlite()..onClose = () => order.add('database');
    final bootstrap = _bootstrap(transport, sqlite: sqlite);
    final system = await _system(bootstrap);
    await bootstrap.initialize(system: system, actor: _actor(1));
    await bootstrap.close();
    await bootstrap.close();
    expect(order, ['transport', 'database']);
    expect(
      bootstrap.syncCoordinator!.snapshot.connection,
      SyncConnectionState.closed,
    );
  });

  test(
    'shutdown during initialization does not start a transport later',
    () async {
      final transport = TestTransport();
      final sqlite = _ObservedSqlite();
      final bootstrap = _bootstrap(transport, sqlite: sqlite);
      final system = await _system(bootstrap);
      sqlite.holdNextTransaction = true;
      final initialization = bootstrap.initialize(
        system: system,
        actor: _actor(1),
      );
      await sqlite.transactionHeld.future;
      final closing = bootstrap.close();
      sqlite.releaseTransaction.complete();
      await initialization;
      await closing;
      expect(transport.starts, 0);
      expect(bootstrap.syncCoordinator, isNull);
    },
  );

  test(
    'two bootstrapped Notes instances exchange commands in memory',
    () async {
      final firstTransport = TestTransport();
      final secondTransport = TestTransport();
      final first = _bootstrap(firstTransport);
      final second = _bootstrap(secondTransport);
      final firstSystem = await _system(first);
      final secondSystem = await _system(second);
      await _pairIdentities(firstSystem, secondSystem);
      final firstApp = await first.initialize(
        system: firstSystem,
        actor: _actor(1),
      );
      final secondApp = await second.initialize(
        system: secondSystem,
        actor: _actor(2),
      );
      await firstApp.command.createNote('shared-note');
      final catchup = secondSystem.eventStore.commandChanges.first;
      final pair = SyncTestHelper.createPeerPair(
        firstActor: _actor(1),
        secondActor: _actor(2),
      );
      firstTransport.discovery.add(pair.first);
      secondTransport.discovery.add(pair.second);
      await catchup.timeout(const Duration(seconds: 5));
      expect(await secondApp.query.noteList(), hasLength(1));

      final live = firstSystem.eventStore.commandChanges.firstWhere(
        (change) => change.origin == ChangeOrigin.remote,
      );
      await secondApp.command.updateNoteTitle(
        'shared-note',
        'From the other device',
      );
      await live.timeout(const Duration(seconds: 5));
      expect(
        (await firstApp.query.note('shared-note')).title,
        'From the other device',
      );
      expect(first.syncCoordinator!.snapshot.activePeers, [_actor(2)]);
      expect(second.syncCoordinator!.snapshot.activePeers, [_actor(1)]);
    },
  );

  test('reset stops replication with a SQLite write response still pending', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notes-sync-reset-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final filepath = '${directory.path}/main.sqlite';
    final transport = TestTransport();
    final sqlite = _ObservedSqlite();
    final bootstrap = _bootstrap(transport, sqlite: sqlite);
    final system = await _system(bootstrap, filepath: filepath);
    await system.identities.addPeer(
      PeerActorIdentity(publicKey: PublicKey.staticValue(2)),
    );
    await bootstrap.initialize(system: system, actor: _actor(1));
    final pair = SyncTestHelper.createPeerPair(
      firstActor: _actor(1),
      secondActor: _actor(2),
    );
    final codec = const ReplicationMessageCodec();
    final subscribed = Completer<void>();
    final messages = <ReplicationMessage>[];
    final subscription = pair.second.channel.stream.listen((message) {
      final decoded = codec.decode(message);
      messages.add(decoded);
      if (decoded is ReplicationMessageDependency) subscribed.complete();
    });
    addTearDown(subscription.cancel);
    transport.discovery.add(pair.first);
    await subscribed.future.timeout(const Duration(seconds: 5));
    // Use a real Notes command so the received write follows the normal codec.
    final sourceBootstrap = _bootstrap(TestTransport());
    final sourceSystem = await _system(sourceBootstrap, enabled: false);
    final sourceApp = await sourceBootstrap.initialize(
      system: sourceSystem,
      actor: _actor(2),
    );
    await sourceApp.command.createNote('incoming-note');
    final command = await sourceSystem.eventStore.getStoredCommand(
      CommandId(_actor(2), 1),
    );
    sqlite.holdNextTransaction = true;
    pair.second.channel.sink.add(
      codec.encode(ReplicationMessageCommand(command!)),
    );
    await sqlite.transactionHeld.future.timeout(const Duration(seconds: 5));
    await resetDatabase(bootstrap, filepath);
    expect(transport.closed, isTrue);
    expect(File(filepath).existsSync(), isFalse);
    final published = system.eventStore.commandChanges.first;
    sqlite.releaseTransaction.complete();
    await published.timeout(const Duration(seconds: 5));
    expect(messages.whereType<ReplicationMessageCommandAck>(), isEmpty);
    expect(bootstrap.syncCoordinator!.snapshot.activePeers, isEmpty);
  });
}

String _actor(int value) => PublicKey.staticValue(value).toString();

NoteBootstrap _bootstrap(
  TestTransport transport, {
  IsolateSqlite? sqlite,
  NoteTransportFactory? createTransport,
}) {
  final bootstrap = NoteBootstrap(
    logger: const NoopLogger(),
    timeProvider: FakeTimeProviderStatic.zero(),
    sqlite: sqlite,
    createTransport:
        createTransport ??
        ({required url, required actor, required group}) => transport,
  );
  addTearDown(bootstrap.close);
  return bootstrap;
}

Future<NoteSystem> _system(
  NoteBootstrap bootstrap, {
  bool? enabled = true,
  String? url = 'ws://example.test',
  String? group = 'notes',
  String filepath = IsolateSqlite.memoryFilename,
}) async {
  final system = await bootstrap.initializeSystem(dbFilepath: filepath);
  if (enabled != null) {
    await system.kv.setBool(NoteSystem.syncEnabledKey, enabled);
  }
  if (url != null) await system.kv.setString(NoteSystem.serverUrlKey, url);
  if (group != null) await system.kv.setString(NoteSystem.groupKey, group);
  return system;
}

Future<void> _pairIdentities(NoteSystem first, NoteSystem second) async {
  await first.identities.addPeer(
    PeerActorIdentity(publicKey: PublicKey.staticValue(2)),
  );
  await second.identities.addPeer(
    PeerActorIdentity(publicKey: PublicKey.staticValue(1)),
  );
}

class _ObservedSqlite extends IsolateSqlite {
  // Migrations capture the database in isolate messages. Keep test-only
  // completers and callbacks outside that object graph.
  static final _observations = Expando<_SqliteObservation>();

  _ObservedSqlite() {
    _observations[this] = _SqliteObservation();
  }

  _SqliteObservation get _observation => _observations[this]!;
  set onClose(void Function() callback) => _observation.onClose = callback;
  set holdNextTransaction(bool value) =>
      _observation.holdNextTransaction = value;
  Completer<void> get transactionHeld => _observation.transactionHeld;
  Completer<void> get releaseTransaction => _observation.releaseTransaction;

  @override
  Future<T> transaction<T>(T Function(SyncContext) action) async {
    final hold = _observation.holdNextTransaction;
    holdNextTransaction = false;
    final result = await super.transaction(action);
    if (hold) {
      transactionHeld.complete();
      await releaseTransaction.future;
    }
    return result;
  }

  @override
  Future<void> close() async {
    _observation.onClose?.call();
    await super.close();
  }
}

class _SqliteObservation {
  void Function()? onClose;
  bool holdNextTransaction = false;
  final transactionHeld = Completer<void>();
  final releaseTransaction = Completer<void>();
}

Future<NoteSystem> _memorySystem(Kv kv) async {
  await kv.setAll({
    NoteSystem.syncEnabledKey: true,
    NoteSystem.serverUrlKey: 'ws://example.test',
    NoteSystem.groupKey: 'notes',
  });
  return NoteSystem(
    identities: MemoryActorIdentityStore(),
    kv: kv,
    eventStore: MemoryEventStore(),
  );
}

class _DelayedKv extends MemoryKv {
  Completer<void>? gate;
  bool failReads = false;

  @override
  Future<String?> getString(String key) async {
    final held = gate;
    if (failReads) throw Exception('read failed');
    final value = await super.getString(key);
    await held?.future;
    return value;
  }
}
