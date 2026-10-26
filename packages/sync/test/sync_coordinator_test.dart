import 'dart:async';
import 'dart:typed_data';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';
import 'package:transport/transport.dart';
import 'package:transport_test/transport_test.dart';

import 'sync_test_utils.dart';

void main() {
  test('failure timestamps update only when a new failure occurs', () async {
    final h = await _Harness.create();
    await flushMessages();
    expect(h.coordinator.snapshot.lastFailureAt, isNull);
    await h.clock.elapse(const Duration(seconds: 3));
    h.transports.last.discovery.addError(Exception('offline'));
    await flushMessages();
    final firstFailureAt = h.clock.now();
    expect(h.coordinator.snapshot.lastFailureAt, firstFailureAt);

    await h.clock.elapse(SyncDefaults.reconnectInterval);
    expect(h.coordinator.snapshot.connection, SyncConnectionState.connected);
    expect(h.coordinator.snapshot.lastFailureAt, firstFailureAt);

    h.transports.last.discovery.addError(Exception('offline again'));
    await flushMessages();
    expect(h.coordinator.snapshot.lastFailureAt, h.clock.now());
    expect(h.coordinator.snapshot.lastFailureAt, isNot(firstFailureAt));
  });

  for (final interval in [Duration.zero, const Duration(seconds: -1)]) {
    test('rejects nonpositive reconnect interval $interval', () {
      expect(
        () => _Harness._(reconnectInterval: interval),
        throwsArgumentError,
      );
    });
  }

  for (final hangs in [false, true]) {
    test('retries at ten-second intervals when startup hangs=$hangs', () async {
      final h = await _Harness.create(start: false);
      final pending = <Completer<void>>[];
      h.onStart = () {
        if (!hangs) return Future.error(Exception('offline'));
        final attempt = Completer<void>();
        pending.add(attempt);
        return attempt.future;
      };
      h.coordinator.start();
      await flushMessages();
      expect(h.attempts, 1);
      for (final attempts in [2, 3]) {
        await h.clock.elapse(const Duration(seconds: 9));
        expect(h.attempts, attempts - 1);
        await h.clock.elapse(const Duration(seconds: 1));
        expect(h.attempts, attempts);
        expect(h.transports[attempts - 2].closes, greaterThanOrEqualTo(1));
      }
      if (hangs) {
        expect(
          h.coordinator.snapshot.lastFailure,
          'Sync connection attempt timed out',
        );
      }
      h.onStart = null;
      await h.clock.elapse(const Duration(seconds: 10));
      expect(h.attempts, 4);
      expect(h.coordinator.snapshot.connection, SyncConnectionState.connected);
      for (final attempt in pending) {
        attempt.complete();
      }
      await flushMessages();
      expect(h.transports.last.closes, 0);
      await h.clock.elapse(const Duration(seconds: 30));
      expect(h.attempts, 4);
      expect(h.clock.activeTimers, 0);
    });
  }

  test('late startup failure keeps the original attempt deadline', () async {
    final h = await _Harness.create(start: false);
    final starting = Completer<void>();
    h.onStart = () => starting.future;
    h.coordinator.start();
    await h.clock.elapse(const Duration(seconds: 7));
    starting.completeError(Exception('offline'));
    await flushMessages();
    h.onStart = null;
    await h.clock.elapse(const Duration(seconds: 3));
    expect(h.attempts, 2);
    expect(h.coordinator.snapshot.connection, SyncConnectionState.connected);
  });

  test(
    'diagnostics follow connection recovery and retain the last failure',
    () async {
      final h = await _Harness.create(start: false);
      final snapshots = <SyncSnapshot>[];
      final subscription = h.coordinator.changes.listen(snapshots.add);
      addTearDown(subscription.cancel);
      expect(h.coordinator.snapshot.connection, SyncConnectionState.idle);
      h.coordinator.start();
      expect(h.coordinator.snapshot.connection, SyncConnectionState.connecting);
      await flushMessages();
      expect(h.coordinator.snapshot.connection, SyncConnectionState.connected);

      h.transports.single.discovery.addError(Exception('private data'));
      await flushMessages();
      expect(
        h.coordinator.snapshot.connection,
        SyncConnectionState.reconnecting,
      );
      final failure = h.coordinator.snapshot.lastFailure;
      expect(failure, 'Sync transport ended; scheduling reconnect');
      await h.clock.elapse(const Duration(seconds: 10));
      expect(h.coordinator.snapshot.connection, SyncConnectionState.connected);
      expect(h.coordinator.snapshot.lastFailure, failure);
      await h.coordinator.close();
      await flushMessages();
      expect(snapshots.map((s) => s.connection), [
        SyncConnectionState.connecting,
        SyncConnectionState.connected,
        SyncConnectionState.reconnecting,
        SyncConnectionState.connecting,
        SyncConnectionState.connected,
        SyncConnectionState.closed,
      ]);
    },
  );

  test('diagnostics list admitted peers until their session closes', () async {
    final h = await _Harness.create();
    final lookup = Completer<PeerActorIdentity?>();
    h.identities.lookup = () => lookup.future;
    final peer = h.discover();
    await flushMessages();
    expect(h.coordinator.snapshot.activePeers, isEmpty);
    final identity = (await h.identities.allPeers()).first;
    lookup.complete(identity);
    await flushMessages();
    final admitted = h.coordinator.snapshot;
    expect(admitted.activePeers, [identity.publicKey.toString()]);
    expect(() => admitted.activePeers.clear(), throwsUnsupportedError);
    await peer.channel.foreign.sink.close();
    await flushMessages();
    expect(h.coordinator.snapshot.activePeers, isEmpty);
    expect(admitted.activePeers, hasLength(1));
  });

  test('unknown peers never appear in diagnostics', () async {
    final h = await _Harness.create();
    h.discover(actor: PublicKey.staticValue(3).toString());
    await flushMessages();
    expect(h.coordinator.snapshot.activePeers, isEmpty);
    expect(h.coordinator.snapshot.lastFailure, isNull);
  });

  test('replication failures appear without exposing raw errors', () async {
    final h = await _Harness.create();
    h.store.readState = () async => throw Exception('private data');
    h.discover();
    await flushMessages();
    expect(
      h.coordinator.snapshot.lastFailure,
      'Sync command replication failed',
    );
    expect(h.coordinator.snapshot.activePeers, isEmpty);
  });

  test('close publishes a final snapshot and closes diagnostics', () async {
    final h = await _Harness.create();
    h.discover();
    await flushMessages();
    final snapshots = h.coordinator.changes.toList();
    await h.coordinator.close();
    expect(h.coordinator.snapshot.connection, SyncConnectionState.closed);
    expect(h.coordinator.snapshot.activePeers, isEmpty);
    expect((await snapshots).last.connection, SyncConnectionState.closed);
  });

  test('known peers exchange stored commands through the codec', () async {
    final h = await _Harness.create();
    final peer = h.discover();
    await flushMessages();
    expect(peer.messages.single, isA<CommandReplicationMessageDependency>());

    final command = _command();
    peer.send(CommandReplicationMessageCommand(command));
    await flushMessages();

    expect(await h.store.getStoredCommand(command.commandId), isNotNull);
    expect(peer.messages.last, isA<CommandReplicationMessageCommandAck>());
    await h.store.addStoredCommand(_command(actor: 'local'));
    peer.send(CommandReplicationMessageDependency(CommandDependency()));
    await flushMessages();
    expect(peer.messages.last, isA<CommandReplicationMessageCommand>());
    expect(peer.closed, isFalse);
  });

  test('unknown peers are closed without starting replication', () async {
    final h = await _Harness.create();
    final peer = h.discover(actor: PublicKey.staticValue(3).toString());
    await flushMessages();
    expect(peer.closed, isTrue);
    expect(peer.messages, isEmpty);
  });

  for (final failure in [
    Exception('private data'),
    StateError('private data'),
  ]) {
    test('identity lookup failure $failure closes only that session', () async {
      final h = await _Harness.create();
      h.identities.lookup = () async => throw failure;
      final peer = h.discover();
      await flushMessages();
      expect(peer.closed, isTrue);
      expect(h.clock.activeTimers, 0);
      expect(h.transports.single.closes, 0);
      _expectSafeLogs(h.logger);
    });
  }

  test('identity removal leaves active sessions open', () async {
    final h = await _Harness.create();
    final peer = h.discover();
    await flushMessages();
    await h.identities.deleteAllPeers();
    peer.send(CommandReplicationMessageCommand(_command()));
    await flushMessages();
    expect(peer.closed, isFalse);
    expect(peer.messages.last, isA<CommandReplicationMessageCommandAck>());
  });

  test('identity removal blocks a later admission', () async {
    final h = await _Harness.create();
    h.discover();
    await flushMessages();
    await h.identities.deleteAllPeers();
    final replacement = h.discover();
    await flushMessages();
    expect(replacement.closed, isTrue);
    expect(replacement.messages, isEmpty);
  });

  for (final cause in ['factory', 'startup', 'stream error', 'stream done']) {
    test('$cause schedules exactly one delayed replacement', () async {
      final h = await _Harness.create(start: false);
      final starting = Completer<void>();
      if (cause == 'factory') h.factoryFailure = Exception('private data');
      if (cause == 'startup') h.onStart = () => starting.future;
      h.coordinator.start();
      if (cause != 'factory') {
        final transport = h.transports.single;
        switch (cause) {
          case 'startup':
            starting.completeError(Exception('private data'));
          case 'stream error':
            transport.discovery.addError(Exception('private data'));
            transport.discovery.addError(Exception('private data'));
          case 'stream done':
            unawaited(transport.discovery.close());
        }
      }
      await flushMessages();
      expect(h.clock.activeTimers, 1);
      final attempts = h.attempts;
      await h.clock.elapse(const Duration(seconds: 9));
      expect(h.attempts, attempts);
      h.factoryFailure = null;
      h.onStart = null;
      await h.clock.elapse(const Duration(seconds: 1));
      expect(h.attempts, attempts + 1);
      expect(h.clock.activeTimers, 0);
      expect(h.transports.last.starts, 1);
      _expectSafeLogs(h.logger);
    });
  }

  test('recovery retires active and pending sessions', () async {
    final h = await _Harness.create();
    final active = h.discover();
    await flushMessages();
    final lookup = Completer<PeerActorIdentity?>();
    h.identities.lookup = () => lookup.future;
    final pending = h.discover(
      actor: (await h.identities.allPeers()).last.publicKey.toString(),
    );
    await flushMessages();
    h.transports.single.discovery.addError(Exception('disconnected'));
    await flushMessages();
    expect(active.closed, isTrue);
    expect(pending.closed, isTrue);
    lookup.complete((await h.identities.allPeers()).last);
    await flushMessages();
    expect(pending.messages, isEmpty);
  });

  test('recovery uses the configured interval', () async {
    final h = await _Harness.create(
      reconnectInterval: const Duration(seconds: 2),
    );
    h.transports.single.discovery.addError(Exception('disconnected'));
    await flushMessages();
    await h.clock.elapse(const Duration(seconds: 1));
    expect(h.attempts, 1);
    await h.clock.elapse(const Duration(seconds: 1));
    expect(h.attempts, 2);
  });

  test('late startup failure cannot restart a replacement transport', () async {
    final h = await _Harness.create(start: false);
    final starting = Completer<void>();
    h.onStart = () => starting.future;
    h.coordinator.start();
    h.transports.single.discovery.addError(Exception('disconnected'));
    await flushMessages();
    h.onStart = null;
    await h.clock.elapse(const Duration(seconds: 10));
    starting.completeError(StateError('late startup failure'));
    await flushMessages();
    expect(h.clock.activeTimers, 0);
    expect(h.transports.last.closes, 0);
  });

  for (final failure in [
    Exception('private data'),
    StateError('private data'),
  ]) {
    test('replication failure $failure is contained to one session', () async {
      final h = await _Harness.create();
      final first = h.discover();
      final second = h.discover(
        actor: (await h.identities.allPeers()).last.publicKey.toString(),
      );
      await flushMessages();
      h.store.readState = () async => throw failure;
      final failing = h.discover();
      await flushMessages();
      expect(first.closed, isTrue);
      expect(failing.closed, isFalse);
      expect(second.closed, isFalse);
      expect(h.transports.single.closes, 0);
      expect(h.clock.activeTimers, 1);
      second.send(CommandReplicationMessageCommand(_command()));
      await flushMessages();
      expect(second.messages.last, isA<CommandReplicationMessageCommandAck>());
      _expectSafeLogs(h.logger);
    });
  }

  test(
    'malformed command data restarts commands on the same connection',
    () async {
      final h = await _Harness.create();
      final peer = h.discover();
      await flushMessages();
      peer.multiplexer.channel('commands').sink.add('private data');
      await flushMessages();
      expect(peer.closed, isFalse);
      expect(h.transports.single.closes, 0);
      expect(h.coordinator.snapshot.activePeers, isEmpty);
      await h.clock.elapse(SyncDefaults.reconnectInterval);
      expect(
        peer.messages.whereType<CommandReplicationMessageDependency>(),
        hasLength(2),
      );
      peer.send(CommandReplicationMessageCommand(_command()));
      await flushMessages();
      expect(peer.messages.last, isA<CommandReplicationMessageCommandAck>());
      _expectSafeLogs(h.logger);
    },
  );

  test(
    'persistent command failure retries at the configured interval',
    () async {
      final h = await _Harness.create(
        reconnectInterval: const Duration(seconds: 2),
      );
      h.store.readState = () async => throw Exception('private data');
      final peer = h.discover();
      await flushMessages();
      expect(h.store.stateReads, 1);
      await h.clock.elapse(const Duration(seconds: 1));
      expect(h.store.stateReads, 1);
      await h.clock.elapse(const Duration(seconds: 1));
      expect(h.store.stateReads, 2);
      expect(peer.closed, isFalse);
      expect(h.clock.activeTimers, 1);
      await h.coordinator.close();
      await h.clock.elapse(const Duration(seconds: 4));
      expect(h.store.stateReads, 2);
      expect(h.clock.activeTimers, 0);
    },
  );

  test('connection closure cancels a pending command restart', () async {
    final h = await _Harness.create();
    final peer = h.discover();
    await flushMessages();
    peer.multiplexer.channel('commands').sink.add('malformed command');
    await flushMessages();
    expect(h.clock.activeTimers, 1);
    await peer.multiplexer.close();
    await h.clock.elapse(SyncDefaults.reconnectInterval);
    expect(h.clock.activeTimers, 0);
    expect(h.store.stateReads, 1);
    expect(h.coordinator.snapshot.activePeers, isEmpty);
  });

  test(
    'late command work cannot affect a restarted protocol session',
    () async {
      final h = await _Harness.create();
      final peer = h.discover();
      await flushMessages();
      final saving = Completer<bool>();
      h.store.save = (_) => saving.future;
      peer.send(CommandReplicationMessageCommand(_command()));
      await flushMessages();
      await peer.multiplexer.channel('commands').sink.close();
      await flushMessages();
      await h.clock.elapse(SyncDefaults.reconnectInterval);
      expect(
        peer.messages.whereType<CommandReplicationMessageDependency>(),
        hasLength(2),
      );
      saving.completeError(Exception('late failure'));
      await flushMessages();
      expect(h.coordinator.snapshot.activePeers, hasLength(1));
      expect(h.coordinator.snapshot.lastFailure, isNull);
      expect(peer.closed, isFalse);
      h.store.save = null;
      peer.send(CommandReplicationMessageCommand(_command()));
      await flushMessages();
      expect(peer.messages.last, isA<CommandReplicationMessageCommandAck>());
    },
  );

  test(
    'both coordinators resume command exchange after a write failure',
    () async {
      final first = await _Harness.create();
      final second = await _Harness.create();
      final pair = createMemoryPeerPair(
        firstActor: PublicKey.staticValue(1).toString(),
        secondActor: PublicKey.staticValue(2).toString(),
      );
      second.store.save = (_) async => throw Exception('write failed');
      await first.store.addStoredCommand(_command());
      first.transports.single.discovery.add(pair.first);
      second.transports.single.discovery.add(pair.second);
      await flushMessages();
      expect(
        second.coordinator.snapshot.lastFailure,
        'Sync command replication failed',
      );
      expect(await second.store.getStoredCommand(_command().commandId), isNull);
      second.store.save = null;
      await first.clock.elapse(SyncDefaults.reconnectInterval);
      await second.clock.elapse(SyncDefaults.reconnectInterval);
      expect(
        await second.store.getStoredCommand(_command().commandId),
        isNotNull,
      );
      final reverse = _command(actor: 'reverse');
      await second.store.addStoredCommand(reverse);
      await flushMessages();
      expect(await first.store.getStoredCommand(reverse.commandId), isNotNull);
      expect(first.coordinator.snapshot.activePeers, hasLength(1));
      expect(second.coordinator.snapshot.activePeers, hasLength(1));
      expect(first.transports.single.closes, 0);
      expect(second.transports.single.closes, 0);
    },
  );

  test('commands ignore superseded retry callbacks', () async {
    final h = await _Harness.create(
      reconnectInterval: const Duration(seconds: 2),
    );
    final peer = h.discover();
    await flushMessages();
    StreamChannel<String> channel() => peer.multiplexer.channel('commands');
    await channel().sink.close();
    await flushMessages();
    final stale = h.callbacks.last;
    await h.clock.elapse(const Duration(seconds: 1));
    await channel().sink.close();
    await flushMessages();
    stale();
    await flushMessages();
    expect(h.clock.activeTimers, 1);
    expect(h.store.stateReads, 1);
    await h.clock.elapse(const Duration(seconds: 1));
    expect(h.clock.activeTimers, 1);
    await h.clock.elapse(const Duration(seconds: 1));
    expect(h.clock.activeTimers, 0);
    peer.send(CommandReplicationMessageCommand(_command()));
    await flushMessages();
    expect(peer.messages.last, isA<CommandReplicationMessageCommandAck>());
  });

  for (final cause in [
    'peer replacement',
    'peer closure',
    'transport',
    'close',
  ]) {
    test('$cause cancels the command retry', () async {
      final h = await _Harness.create(
        reconnectInterval: const Duration(seconds: 2),
      );
      final peer = h.discover();
      await flushMessages();
      peer.multiplexer.channel('commands').sink.add('private data');
      await flushMessages();
      expect(h.clock.activeTimers, 1);
      final callbacks = h.callbacks.skip(1).toList();
      switch (cause) {
        case 'peer replacement':
          h.discover();
        case 'peer closure':
          await peer.multiplexer.close();
        case 'transport':
          h.transports.single.discovery.addError(Exception('private data'));
        case 'close':
          await h.coordinator.close();
      }
      await flushMessages();
      for (final callback in callbacks) {
        callback();
      }
      await h.clock.elapse(const Duration(seconds: 2));
      expect(h.store.stateReads, cause == 'peer replacement' ? 2 : 1);
      expect(h.clock.activeTimers, 0);
      expect(peer.closed, isTrue);
    });
  }

  test('superseded admission cannot replace the current session', () async {
    final h = await _Harness.create();
    final lookup = Completer<PeerActorIdentity?>();
    h.identities.lookup = () => lookup.future;
    final old = h.discover();
    await flushMessages();
    h.identities.lookup = null;
    final current = h.discover();
    await flushMessages();
    lookup.complete((await h.identities.allPeers()).first);
    await flushMessages();
    expect(old.closed, isTrue);
    expect(old.messages, isEmpty);
    expect(current.closed, isFalse);
    expect(current.messages.single, isA<CommandReplicationMessageDependency>());
  });

  test('channel closure during admission prevents replication', () async {
    final h = await _Harness.create();
    final lookup = Completer<PeerActorIdentity?>();
    h.identities.lookup = () => lookup.future;
    final peer = h.discover();
    await flushMessages();
    await peer.channel.foreign.sink.close();
    await flushMessages();
    lookup.complete((await h.identities.allPeers()).first);
    await flushMessages();
    expect(peer.messages, isEmpty);
    expect(h.store.stateReads, 0);
  });

  test('messages received during admission are retained', () async {
    final h = await _Harness.create();
    final lookup = Completer<PeerActorIdentity?>();
    h.identities.lookup = () => lookup.future;
    final peer = h.discover();
    peer.send(CommandReplicationMessageDependency(CommandDependency()));
    await flushMessages();
    lookup.complete((await h.identities.allPeers()).first);
    await flushMessages();
    expect(peer.closed, isFalse);
    expect(peer.messages.single, isA<CommandReplicationMessageDependency>());
  });

  test('channel errors during admission prevent replication', () async {
    final h = await _Harness.create();
    final lookup = Completer<PeerActorIdentity?>();
    h.identities.lookup = () => lookup.future;
    final peer = h.discover();
    await flushMessages();
    peer.channel.foreign.sink.addError(StateError('private data'));
    await flushMessages();
    lookup.complete((await h.identities.allPeers()).first);
    await flushMessages();
    expect(peer.closed, isTrue);
    expect(h.store.stateReads, 0);
    _expectSafeLogs(h.logger);
  });

  test('old replication completion cannot retire its replacement', () async {
    final h = await _Harness.create();
    final read = Completer<EventDatabaseState>();
    h.store.readState = () => read.future;
    final old = h.discover();
    await flushMessages();
    h.store.readState = null;
    final current = h.discover();
    await flushMessages();
    expect(old.closed, isTrue);
    expect(current.messages.single, isA<CommandReplicationMessageDependency>());
    read.completeError(StateError('private data'));
    await flushMessages();
    expect(current.closed, isFalse);
    await h.coordinator.close();
    await flushMessages();
    expect(current.closed, isTrue);
  });

  test('close during startup is prompt and closes a late startup', () async {
    final h = await _Harness.create(start: false);
    final starting = Completer<void>();
    h.onStart = () => starting.future;
    h.coordinator.start();
    await _closePromptly(h);
    expect(h.transports.single.closes, 1);
    starting.complete();
    await flushMessages();
    expect(h.transports.single.closes, 2);
    expect(h.clock.activeTimers, 0);
  });

  test('close cancels the reconnect delay', () async {
    final h = await _Harness.create();
    h.transports.single.discovery.addError(Exception('disconnected'));
    await flushMessages();
    await _closePromptly(h);
    await h.clock.elapse(const Duration(seconds: 20));
    expect(h.attempts, 1);
    expect(h.clock.activeTimers, 0);
  });

  for (final fails in [false, true]) {
    test('close during identity lookup ignores late result: $fails', () async {
      final h = await _Harness.create();
      final lookup = Completer<PeerActorIdentity?>();
      h.identities.lookup = () => lookup.future;
      final peer = h.discover();
      await flushMessages();
      await _closePromptly(h);
      if (fails) {
        lookup.completeError(StateError('private data'));
      } else {
        lookup.complete((await h.identities.allPeers()).first);
      }
      await flushMessages();
      expect(peer.closed, isTrue);
      expect(peer.messages, isEmpty);
      expect(h.store.stateReads, 0);
    });
  }

  test('close during a blocked store write prevents a late ACK', () async {
    final h = await _Harness.create();
    final save = Completer<bool>();
    h.store.save = (_) => save.future;
    final peer = h.discover();
    await flushMessages();
    peer.send(CommandReplicationMessageCommand(_command()));
    await flushMessages();
    expect(h.store.saves, 1);
    await _closePromptly(h);
    await flushMessages();
    expect(peer.closed, isTrue);
    save.complete(true);
    await flushMessages();
    expect(peer.messages, hasLength(1));
  });

  test('replacement proceeds while the old store write is blocked', () async {
    final h = await _Harness.create();
    final save = Completer<bool>();
    h.store.save = (_) => save.future;
    final old = h.discover();
    await flushMessages();
    old.send(CommandReplicationMessageCommand(_command()));
    await flushMessages();
    expect(h.store.saves, 1);
    final replacement = h.discover();
    await flushMessages();
    expect(old.closed, isTrue);
    expect(
      replacement.messages.single,
      isA<CommandReplicationMessageDependency>(),
    );
    save.complete(true);
    await flushMessages();
    expect(old.messages, hasLength(1));
    expect(replacement.closed, isFalse);
  });

  test('blocked peer cleanup does not delay shutdown', () async {
    final h = await _Harness.create();
    final cancelled = Completer<void>();
    var cancellationStarted = false;
    final incoming = StreamController<String>(
      onCancel: () {
        cancellationStarted = true;
        return cancelled.future;
      },
    );
    // An unlistened outgoing stream keeps sink.close() pending.
    final outgoing = StreamController<String>();
    h.transports.single.discovery.add(
      PeerTransport(
        actor: (await h.identities.allPeers()).first.publicKey.toString(),
        channel: StreamChannel(incoming.stream, outgoing.sink),
      ),
    );
    await flushMessages();
    await _closePromptly(h);
    expect(cancellationStarted, isTrue);
    cancelled.completeError(StateError('private data'));
    await outgoing.stream.drain<void>();
    await incoming.close();
    await flushMessages();
    expect(
      h.logger.entries.any((entry) => entry.message == 'Sync cleanup failed'),
      isTrue,
    );
    _expectSafeLogs(h.logger);
  });

  test(
    'blocked cleanup does not delay close and late failures are observed',
    () async {
      final h = await _Harness.create();
      await flushMessages();
      final closing = Completer<void>();
      final cancelling = Completer<void>();
      h.transports.single.onClose = () => closing.future;
      h.transports.single.discovery.onCancel = () => cancelling.future;
      await _closePromptly(h);
      closing.completeError(StateError('private data'));
      cancelling.completeError(Exception('private data'));
      await flushMessages();
      expect(
        h.logger.entries.where(
          (entry) => entry.message == 'Sync cleanup failed',
        ),
        hasLength(2),
      );
      _expectSafeLogs(h.logger);
    },
  );

  test('repeated closure is safe and leaves injected stores usable', () async {
    final h = await _Harness.create();
    await flushMessages();
    await h.coordinator.close();
    await h.coordinator.close();
    expect(h.transports.single.closes, 1);
    expect(await h.identities.allPeers(), hasLength(2));
    expect(await h.store.addStoredCommand(_command()), isTrue);
  });

  test('repeated startup throws', () async {
    final h = await _Harness.create();
    expect(h.coordinator.start, throwsStateError);
  });

  test('startup after closure throws', () async {
    final h = await _Harness.create(start: false);
    await h.coordinator.close();
    expect(h.coordinator.start, throwsStateError);
    expect(h.attempts, 0);
  });
}

class _Harness {
  final store = _Store();
  final identities = _Identities();
  final logger = RecordingLogger();
  final clock = TestClock();
  final transports = <_Transport>[];
  final callbacks = <void Function()>[];
  Future<void> Function()? onStart;
  Object? factoryFailure;
  int attempts = 0;
  late final SyncCoordinator coordinator;

  _Harness._({Duration? reconnectInterval}) {
    coordinator = SyncCoordinator(
      eventStore: store,
      identityStore: identities,
      logger: logger,
      timeProvider: clock,
      timerFactory: (delay, callback) {
        callbacks.add(callback);
        return clock.schedule(delay, callback);
      },
      reconnectInterval: reconnectInterval ?? SyncDefaults.reconnectInterval,
      createTransport: () {
        attempts++;
        if (factoryFailure != null) throw factoryFailure!;
        final transport = _Transport()..onStart = onStart;
        transports.add(transport);
        return transport;
      },
    );
    addTearDown(coordinator.close);
  }

  static Future<_Harness> create({
    bool start = true,
    Duration? reconnectInterval,
  }) async {
    final harness = _Harness._(reconnectInterval: reconnectInterval);
    for (final value in [1, 2]) {
      await harness.identities.addPeer(
        PeerActorIdentity(publicKey: PublicKey.staticValue(value)),
      );
    }
    if (start) harness.coordinator.start();
    return harness;
  }

  _Peer discover({String? actor}) {
    final peer = _Peer();
    transports.last.discovery.add(
      PeerTransport(
        actor: actor ?? PublicKey.staticValue(1).toString(),
        channel: peer.channel.local,
      ),
    );
    return peer;
  }
}

class _Transport implements Transport {
  final discovery = StreamController<PeerTransport>();
  Future<void> Function()? onStart;
  Future<void> Function()? onClose;
  int starts = 0;
  int closes = 0;

  @override
  Stream<PeerTransport> get peerTransports => discovery.stream;

  @override
  Future<void> start() {
    expect(discovery.hasListener, isTrue);
    starts++;
    return onStart?.call() ?? Future<void>.value();
  }

  @override
  Future<void> close() {
    closes++;
    return onClose?.call() ?? discovery.close();
  }
}

class _Identities extends MemoryActorIdentityStore {
  Future<PeerActorIdentity?> Function()? lookup;

  @override
  Future<PeerActorIdentity?> getPeer(PublicKey publicKey) =>
      lookup?.call() ?? super.getPeer(publicKey);
}

class _Peer {
  final channel = StreamChannelController<String>();
  final messages = <CommandReplicationMessage>[];
  bool closed = false;
  late final PeerMultiplexer multiplexer;

  _Peer() {
    multiplexer = PeerMultiplexer(channel.foreign);
    unawaited(channel.foreign.sink.done.then((_) => closed = true));
    multiplexer.sessions('commands').listen((session) {
      if (!identical(multiplexer.channel('commands'), session)) return;
      session.stream.listen(
        (value) =>
            messages.add(const CommandReplicationMessageCodec().decode(value)),
      );
    });
    addTearDown(multiplexer.close);
  }

  void send(CommandReplicationMessage message) => multiplexer
      .channel('commands')
      .sink
      .add(const CommandReplicationMessageCodec().encode(message));
}

class _Store implements EventStoreReplication {
  final store = MemoryEventStore();
  Future<EventDatabaseState> Function()? readState;
  Future<bool> Function(StoredCommand)? save;
  int stateReads = 0;
  int saves = 0;

  @override
  Stream<CommandChange> get commandChanges => store.commandChanges;

  @override
  Future<EventDatabaseState> getState() {
    stateReads++;
    return readState?.call() ?? store.getState();
  }

  @override
  Future<bool> addStoredCommand(StoredCommand command) {
    saves++;
    return save?.call(command) ?? store.addStoredCommand(command);
  }

  @override
  Future<StoredCommand?> getStoredCommand(CommandId commandId) =>
      store.getStoredCommand(commandId);

  @override
  Future<List<CommandId>> getNextCommandIds(
    CommandDependency dependency,
    int count,
  ) => store.getNextCommandIds(dependency, count);
}

StoredCommand _command({String actor = 'writer'}) => StoredCommand(
  commandId: CommandId(actor, 1),
  dependency: CommandDependency(),
  occuredAt: DateTime.utc(2026),
  events: [
    StoredCommandEvent(
      streamPath: 'test',
      encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List.fromList([1])),
      occuredAt: DateTime.utc(2026),
    ),
  ],
);

Future<void> _closePromptly(_Harness h) =>
    h.coordinator.close().timeout(const Duration(seconds: 1));

void _expectSafeLogs(RecordingLogger logger) {
  expect(logger.entries, isNotEmpty);
  for (final entry in logger.entries) {
    expect(entry.message, isNot(contains('private data')));
    expect(entry.error, isNull);
    expect(entry.stackTrace, isNull);
  }
}
