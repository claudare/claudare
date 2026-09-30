import 'dart:io';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/reset_database.dart';
import 'package:path/path.dart' as path;
import 'package:sync/sync.dart';
import 'package:time_provider/time_provider.dart';

NoteBootstrap _bootstrap({IsolateSqlite? sqlite}) => NoteBootstrap(
  logger: const NoopLogger(),
  timeProvider: FakeTimeProviderStatic.zero(),
  sqlite: sqlite,
);

void main() {
  for (final actor in [false, true]) {
    for (final server in [false, true]) {
      test('database reopens with actor=$actor and server=$server', () async {
        final directory = await Directory.systemTemp.createTemp('notes-main-');
        addTearDown(() => directory.delete(recursive: true));
        final filepath = path.join(directory.path, 'main.sqlite');
        final first = _bootstrap();
        addTearDown(first.close);
        final system = await first.initializeSystem(dbFilepath: filepath);
        expect(
          await first.initializeSystem(dbFilepath: filepath),
          same(system),
        );
        if (actor) {
          await system.identities.setLocal(
            LocalActorIdentity(publicKey: PublicKey.staticValue(12)),
          );
        }
        if (server) {
          await system.kv.set(NoteSystem.serverUrlKey, 'wss://example.test');
        }
        await first.close();

        final second = _bootstrap();
        addTearDown(second.close);
        final reopened = await second.initializeSystem(dbFilepath: filepath);
        expect(
          (await reopened.identities.getLocal())?.publicKey,
          actor ? PublicKey.staticValue(12) : null,
        );
        expect(
          await reopened.kv.get(NoteSystem.serverUrlKey),
          server ? 'wss://example.test' : null,
        );
      });
    }
  }

  test('shutdown closes the shared database once', () async {
    final sqlite = _CountingSqlite();
    final bootstrap = _bootstrap(sqlite: sqlite);
    final system = await bootstrap.initializeSystem(
      dbFilepath: IsolateSqlite.memoryFilename,
    );
    await bootstrap.initialize(system: system, actor: 'actor');
    await bootstrap.close();
    await bootstrap.close();
    expect(sqlite.closeCount, 1);
  });

  test('shutdown during setup closes the shared database', () async {
    final sqlite = _CountingSqlite();
    final bootstrap = _bootstrap(sqlite: sqlite);
    await bootstrap.initializeSystem(dbFilepath: IsolateSqlite.memoryFilename);
    await bootstrap.close();
    expect(sqlite.closeCount, 1);
  });

  test('configuration migration failure closes the database once', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notes-main-error-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final filepath = path.join(directory.path, 'main.sqlite');
    final seed = IsolateSqlite();
    await seed.open(filepath);
    await seed.execute('CREATE TABLE migrations_kv (wrong INT)');
    await seed.close();
    final sqlite = _CountingSqlite();
    final bootstrap = _bootstrap(sqlite: sqlite);
    await expectLater(
      bootstrap.initializeSystem(dbFilepath: filepath),
      throwsA(isA<Exception>()),
    );
    await bootstrap.close();
    expect(sqlite.closeCount, 1);
  });

  test('new commands use the configured actor', () async {
    final bootstrap = _bootstrap();
    addTearDown(bootstrap.close);
    final actor = PublicKey.staticValue(23).toString();
    final system = await bootstrap.initializeSystem(
      dbFilepath: IsolateSqlite.memoryFilename,
    );
    final application = await bootstrap.initialize(
      system: system,
      actor: actor,
    );
    await application.command.createNote('note');
    final commands = await system.eventStore.getNextCommandIds(
      CommandDependency(),
      10,
    );
    expect(commands.single.actor, actor);
  });

  test(
    'existing event actors remain readable in the shared database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'notes-old-actor-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final filepath = path.join(directory.path, 'main.sqlite');
      final first = _bootstrap();
      addTearDown(first.close);
      final firstSystem = await first.initializeSystem(dbFilepath: filepath);
      final old = await first.initialize(
        system: firstSystem,
        actor: 'notes-dev',
      );
      await old.command.createNote('note');
      await old.command.updateNoteTitle('note', 'Existing note');
      await first.close();

      final second = _bootstrap();
      addTearDown(second.close);
      final system = await second.initializeSystem(dbFilepath: filepath);
      final actor = PublicKey.staticValue(24).toString();
      final application = await second.initialize(system: system, actor: actor);
      expect((await application.query.note('note')).title, 'Existing note');
      await application.command.updateNoteTitle('note', 'Updated note');
      final commands = await system.eventStore.getNextCommandIds(
        CommandDependency(),
        10,
      );
      expect(commands.map((id) => id.actor), ['notes-dev', 'notes-dev', actor]);
    },
  );

  test(
    'a closed database copy carries notes, settings, and pairings',
    () async {
      final directory = await Directory.systemTemp.createTemp('notes-copy-');
      addTearDown(() => directory.delete(recursive: true));
      final filepath = path.join(directory.path, 'main.sqlite');
      final copiedPath = path.join(directory.path, 'copied.sqlite');
      final first = _bootstrap();
      addTearDown(first.close);
      final system = await first.initializeSystem(dbFilepath: filepath);
      final identity = LocalActorIdentity(publicKey: PublicKey.staticValue(45));
      final peer = PeerActorIdentity(publicKey: PublicKey.staticValue(46));
      await system.identities.setLocal(identity);
      await system.identities.addPeer(peer);
      await system.kv.set(NoteSystem.serverUrlKey, 'ws://localhost:7000');
      final application = await first.initialize(
        system: system,
        actor: identity.publicKey.toString(),
      );
      await application.command.createNote('note');
      await application.command.updateNoteTitle('note', 'Copied note');
      await first.close();
      await File(filepath).copy(copiedPath);

      final second = _bootstrap();
      addTearDown(second.close);
      final copied = await second.initializeSystem(dbFilepath: copiedPath);
      expect(
        (await copied.identities.getLocal())!.publicKey,
        identity.publicKey,
      );
      expect(
        (await copied.identities.allPeers()).single.publicKey,
        peer.publicKey,
      );
      expect(
        await copied.kv.get(NoteSystem.serverUrlKey),
        'ws://localhost:7000',
      );
      final restored = await second.initialize(
        system: copied,
        actor: identity.publicKey.toString(),
      );
      expect((await restored.query.note('note')).title, 'Copied note');
    },
  );

  test(
    'database reset clears notes, settings, identity, and pairings',
    () async {
      final directory = await Directory.systemTemp.createTemp('notes-reset-');
      addTearDown(() => directory.delete(recursive: true));
      final filepath = path.join(directory.path, 'main.sqlite');
      final first = _bootstrap();
      addTearDown(first.close);
      final system = await first.initializeSystem(dbFilepath: filepath);
      final identity = LocalActorIdentity(publicKey: PublicKey.staticValue(45));
      await system.identities.setLocal(identity);
      await system.identities.addPeer(
        PeerActorIdentity(publicKey: PublicKey.staticValue(46)),
      );
      await system.kv.set(NoteSystem.serverUrlKey, 'ws://localhost:7000');
      final application = await first.initialize(
        system: system,
        actor: identity.publicKey.toString(),
      );
      await application.command.createNote('note');
      await resetDatabase(first, filepath);
      expect(File(filepath).existsSync(), isFalse);

      final second = _bootstrap();
      addTearDown(second.close);
      final reopened = await second.initializeSystem(dbFilepath: filepath);
      expect(await reopened.identities.getLocal(), isNull);
      expect(await reopened.identities.allPeers(), isEmpty);
      expect(await reopened.kv.list(''), isEmpty);
      expect(
        (await reopened.eventStore.getState()).lastEventLogPosition,
        isNull,
      );
    },
  );

  test('database reset deletes all SQLite sidecars', () async {
    final directory = await Directory.systemTemp.createTemp('notes-sidecars-');
    addTearDown(() => directory.delete(recursive: true));
    final filepath = path.join(directory.path, 'main.sqlite');
    final bootstrap = _bootstrap();
    await bootstrap.initializeSystem(dbFilepath: filepath);
    await bootstrap.close();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      await File('$filepath$suffix').writeAsString('');
    }
    await resetDatabase(bootstrap, filepath);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(File('$filepath$suffix').existsSync(), isFalse);
    }
  });
}

class _CountingSqlite extends IsolateSqlite {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
    await super.close();
  }
}
