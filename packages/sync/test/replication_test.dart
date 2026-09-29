import 'dart:async';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:cqrs/src/cqrs/event/event_append.dart';
import 'package:sync/sync.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('in-memory replication', () {
    test('both peers catch up in causal order without echoes', () async {
      final first = MemoryEventStore();
      final second = MemoryEventStore();
      final shared = _command('shared', 1);
      await _seed(first, [shared]);
      await _seed(second, [shared]);
      final left = _command('left', 1, dependency: {'shared': 1});
      final right = _command('right', 1, dependency: {'shared': 1});
      await _seed(first, [left]);
      await _seed(second, [right]);
      final expected = CommandDependency({'shared': 1, 'left': 1, 'right': 1});
      final caughtUp = Future.wait([
        _whenKnown(first, expected),
        _whenKnown(second, expected),
      ]);
      final link = _Link(first, second);

      await caughtUp;
      await _flush();

      expect(
        (await first.getStoredCommand(right.commandId))!.toJson(),
        right.toJson(),
      );
      expect(
        (await second.getStoredCommand(left.commandId))!.toJson(),
        left.toJson(),
      );
      expect((await first.getState()).lastCommandLogPosition, 2);
      expect((await second.getState()).lastCommandLogPosition, 2);
      expect(link.stopped, isFalse);
    });

    test('new local commands replicate after both peers become idle', () async {
      final first = MemoryEventStore();
      final second = MemoryEventStore();
      final link = _Link(first, second);
      await _flush();

      final firstDelivery = _whenKnown(second, CommandDependency({'left': 1}));
      await _append(first, 'left');
      await firstDelivery;
      final secondDelivery = _whenKnown(first, CommandDependency({'right': 1}));
      await _append(second, 'right');
      await secondDelivery;
      await _flush();

      expect(link.stopped, isFalse);
      expect(
        (await first.getState()).logVersion,
        (await second.getState()).logVersion,
      );
    });

    for (final (leftReceives, rightReceives) in [
      (true, false),
      (false, true),
      (false, false),
    ]) {
      test(
        'subscriptions control receiving: $leftReceives, $rightReceives',
        () async {
          final first = MemoryEventStore();
          final second = MemoryEventStore();
          await _append(first, 'left');
          await _append(second, 'right');
          final link = _Link(
            first,
            second,
            peer1Receives: leftReceives,
            peer2Receives: rightReceives,
          );
          if (leftReceives) {
            await _whenKnown(first, CommandDependency({'right': 1}));
          }
          if (rightReceives) {
            await _whenKnown(second, CommandDependency({'left': 1}));
          }
          await _flush();

          expect(
            (await first.getState()).logVersion.value('right'),
            leftReceives ? 1 : 0,
          );
          expect(
            (await second.getState()).logVersion.value('left'),
            rightReceives ? 1 : 0,
          );
          expect(link.stopped, isFalse);
        },
      );
    }

    test(
      'a save failure stops both peers and surfaces the original failure',
      () async {
        final first = MemoryEventStore();
        final second = _ControlledStore();
        final failure = const FormatException('save failed');
        second.save = (_) async => throw failure;
        await _append(first, 'left');
        final link = _Link(first, second);

        await link.finished;

        expect(link.failure, same(failure));
        expect(second.listeners, 0);
      },
    );

    test(
      'closing either peer ends the session while an ACK is pending',
      () async {
        final first = _ControlledStore();
        final second = _ControlledStore();
        final saving = Completer<void>();
        final release = Completer<void>();
        second.save = (command) async {
          saving.complete();
          await release.future;
          return second.store.addStoredCommand(command);
        };
        await _append(first.store, 'left');
        final link = _Link(first, second);
        await saving.future;

        final closing = link.replication.peer1.close();
        release.complete();
        await closing;
        await link.finished;

        expect(link.failure, isNull);
        expect(first.listeners, 0);
        expect(second.listeners, 0);
      },
    );
  });

  group('replication protocol', () {
    test('subscription advertises the current stored history', () async {
      final store = MemoryEventStore();
      await _seed(store, [_command('local', 1)]);
      final peer = _Peer(store);

      final message = await peer.next<ReplicationMessageDependency>();

      expect(message.dependencies, CommandDependency({'local': 1}));
    });

    test('sends only one command until its matching ACK', () async {
      final store = MemoryEventStore();
      await _seed(store, [_command('local', 1), _command('local', 2)]);
      final peer = _Peer(store, receive: false);
      peer.send(ReplicationMessageDependency(CommandDependency()));
      final first = await peer.next<ReplicationMessageCommand>();
      await _flush();
      expect(peer.messages, hasLength(1));

      peer.send(ReplicationMessageCommandAck(first.command.commandId));

      final second = await peer.next<ReplicationMessageCommand>();
      expect(second.command.commandId, const CommandId('local', 2));
    });

    test('receiving a command does not subscribe the peer', () async {
      final store = MemoryEventStore();
      final peer = _Peer(store);
      await peer.next<ReplicationMessageDependency>();
      final command = _command('remote', 1);

      peer.send(ReplicationMessageCommand(command));
      expect(
        (await peer.next<ReplicationMessageCommandAck>()).commandId,
        command.commandId,
      );
      await _append(store, 'local');
      await _flush();
      expect(peer.messages, hasLength(2));
      expect(peer.stopped, isFalse);
    });

    test('a late subscription preserves knowledge of received commands', () async {
      final store = MemoryEventStore();
      final peer = _Peer(store);
      await peer.next<ReplicationMessageDependency>();
      peer.send(ReplicationMessageCommand(_command('remote', 1)));
      await peer.next<ReplicationMessageCommandAck>();
      await _append(store, 'local');

      // A late, older snapshot must not erase knowledge of the remote command.
      peer.send(ReplicationMessageDependency(CommandDependency()));
      final next = await peer.next<ReplicationMessageCommand>();
      expect(next.command.commandId, const CommandId('local', 1));
      peer.send(ReplicationMessageCommandAck(next.command.commandId));
      await _flush();
      expect(peer.messages, hasLength(3));
      expect(peer.stopped, isFalse);
    });

    test('received dependencies do not replace an outstanding ACK', () async {
      final store = MemoryEventStore();
      await _seed(store, [
        _command('local', 1),
        _command('local', 2),
        _command('other', 1),
      ]);
      final peer = _Peer(store);
      await peer.next<ReplicationMessageDependency>();
      peer.send(ReplicationMessageDependency(CommandDependency()));
      final pending = await peer.next<ReplicationMessageCommand>();
      peer.send(
        ReplicationMessageCommand(
          _command('remote', 1, dependency: {'local': 2}),
        ),
      );
      await peer.next<ReplicationMessageCommandAck>();
      await _flush();
      expect(peer.messages, hasLength(3));

      peer.send(ReplicationMessageCommandAck(pending.command.commandId));

      final next = await peer.next<ReplicationMessageCommand>();
      expect(next.command.commandId, const CommandId('other', 1));
    });

    test('ACK is emitted only after saving succeeds', () async {
      final store = _ControlledStore();
      final saving = Completer<void>();
      final release = Completer<void>();
      store.save = (command) async {
        saving.complete();
        await release.future;
        return store.store.addStoredCommand(command);
      };
      final peer = _Peer(store);
      await peer.next<ReplicationMessageDependency>();
      final command = _command('remote', 1);
      peer.send(ReplicationMessageCommand(command));
      await saving.future;
      expect(peer.messages, hasLength(1));

      release.complete();

      final ack = await peer.next<ReplicationMessageCommandAck>();
      expect(ack.commandId, command.commandId);
      expect(await store.getStoredCommand(command.commandId), isNotNull);
    });

    test('changes during an ACK wait are delivered afterwards', () async {
      final store = MemoryEventStore();
      await _append(store, 'local');
      final peer = _Peer(store, receive: false);
      peer.send(ReplicationMessageDependency(CommandDependency()));
      final pending = await peer.next<ReplicationMessageCommand>();
      await _append(store, 'local');
      await _flush();
      expect(peer.messages, hasLength(1));

      peer.send(ReplicationMessageCommandAck(pending.command.commandId));

      expect(
        (await peer.next<ReplicationMessageCommand>()).command.commandId,
        const CommandId('local', 2),
      );
    });

    test('a change during an empty catch-up read is not lost', () async {
      final store = _ControlledStore();
      final reading = Completer<void>();
      final release = Completer<List<CommandId>>();
      store.readNext = (dependency, count) {
        store.readNext = null;
        reading.complete();
        return release.future;
      };
      final peer = _Peer(store, receive: false);
      peer.send(ReplicationMessageDependency(CommandDependency()));
      await reading.future;
      await _append(store.store, 'local');

      release.complete([]);

      expect(
        (await peer.next<ReplicationMessageCommand>()).command.commandId,
        const CommandId('local', 1),
      );
    });

    test(
      'writes during the initial state read are included in catch-up',
      () async {
        final store = _ControlledStore();
        final snapshot = await store.getState();
        final reading = Completer<void>();
        final release = Completer<EventDatabaseState>();
        store.readState = () {
          reading.complete();
          return release.future;
        };
        final peer = _Peer(store);
        await reading.future;
        await _append(store.store, 'local');
        peer.send(ReplicationMessageDependency(CommandDependency()));

        release.complete(snapshot);

        await peer.next<ReplicationMessageDependency>();
        expect(
          (await peer.next<ReplicationMessageCommand>()).command.commandId,
          const CommandId('local', 1),
        );
      },
    );

    for (final (name, command) in [
      ('duplicate', _command('local', 1)),
      ('sequence gap', _command('remote', 2)),
      ('missing dependency', _command('remote', 1, dependency: {'missing': 1})),
    ]) {
      test('$name closes without an ACK', () async {
        final store = MemoryEventStore();
        await _seed(store, [_command('local', 1)]);
        final peer = _Peer(store);
        await peer.next<ReplicationMessageDependency>();

        peer.send(ReplicationMessageCommand(command));
        await peer.finished;

        expect(peer.failure, isA<ReplicationException>());
        expect(
          peer.messages.whereType<ReplicationMessageCommandAck>(),
          isEmpty,
        );
        expect((await store.getState()).lastCommandLogPosition, 0);
      });
    }

    for (final failure in [
      const FormatException('save failure'),
      StateError('fatal'),
    ]) {
      test('save failure $failure reaches the caller with its stack', () async {
        final store = _ControlledStore();
        final stack = StackTrace.current;
        store.save = (_) => Future<bool>.error(failure, stack);
        final peer = _Peer(store);
        await peer.next<ReplicationMessageDependency>();

        peer.send(ReplicationMessageCommand(_command('remote', 1)));
        await peer.finished;

        expect(peer.failure, same(failure));
        expect(peer.failureStack, same(stack));
        expect(store.listeners, 0);
        expect(
          peer.messages.whereType<ReplicationMessageCommandAck>(),
          isEmpty,
        );
      });
    }

    test(
      'commands without a local subscription close the connection',
      () async {
        final peer = _Peer(MemoryEventStore(), receive: false);

        peer.send(ReplicationMessageCommand(_command('remote', 1)));
        await peer.finished;

        expect(peer.failure, isA<ReplicationException>());
        expect(peer.messages, isEmpty);
      },
    );

    test(
      'a command arriving before the initial subscription is rejected',
      () async {
        final store = _ControlledStore();
        final reading = Completer<void>();
        final release = Completer<EventDatabaseState>();
        store.readState = () {
          reading.complete();
          return release.future;
        };
        final peer = _Peer(store);
        await reading.future;

        peer.send(ReplicationMessageCommand(_command('remote', 1)));
        await _flush();
        release.complete(await store.store.getState());
        await peer.finished;

        expect(peer.failure, isA<ReplicationException>());
        expect(peer.messages, isEmpty);
        expect((await store.store.getState()).lastCommandLogPosition, isNull);
      },
    );

    test('an ACK arriving before its command is sent is rejected', () async {
      final store = _ControlledStore();
      await _append(store.store, 'local');
      final reading = Completer<void>();
      final release = Completer<List<CommandId>>();
      store.readNext = (_, _) {
        reading.complete();
        return release.future;
      };
      final peer = _Peer(store, receive: false);
      peer.send(ReplicationMessageDependency(CommandDependency()));
      await reading.future;

      peer.send(const ReplicationMessageCommandAck(CommandId('local', 1)));
      await _flush();
      release.complete([const CommandId('local', 1)]);
      await peer.finished;

      expect(peer.failure, isA<ReplicationException>());
      expect(peer.messages, isEmpty);
    });

    test('a repeated subscription closes the connection', () async {
      final peer = _Peer(MemoryEventStore(), receive: false);
      peer.send(ReplicationMessageDependency(CommandDependency()));
      peer.send(ReplicationMessageDependency(CommandDependency()));

      await peer.finished;

      expect(peer.failure, isA<ReplicationException>());
    });

    for (final pending in [false, true]) {
      test('unexpected ACK closes with pending command: $pending', () async {
        final store = MemoryEventStore();
        await _append(store, 'local');
        final peer = _Peer(store, receive: false);
        if (pending) {
          peer.send(ReplicationMessageDependency(CommandDependency()));
          await peer.next<ReplicationMessageCommand>();
        }

        peer.send(const ReplicationMessageCommandAck(CommandId('unknown', 1)));
        await peer.finished;

        expect(peer.failure, isA<ReplicationException>());
      });
    }

    test(
      'channel errors stop the session and surface the original error',
      () async {
        final peer = _Peer(MemoryEventStore());
        await peer.next<ReplicationMessageDependency>();
        final failure = const FormatException('channel failure');

        peer.channel.foreign.sink.addError(failure);
        await peer.finished;

        expect(peer.failure, same(failure));
      },
    );

    test(
      'remote closure releases a pending ACK and store subscription',
      () async {
        final store = _ControlledStore();
        await _append(store.store, 'local');
        final peer = _Peer(store, receive: false);
        peer.send(ReplicationMessageDependency(CommandDependency()));
        await peer.next<ReplicationMessageCommand>();

        await peer.channel.foreign.sink.close();
        await peer.finished;
        await _append(store.store, 'local');
        await _flush();

        expect(peer.failure, isNull);
        expect(store.listeners, 0);
        expect(peer.messages, hasLength(1));
      },
    );

    test('closing during a save emits no late ACK', () async {
      final store = _ControlledStore();
      final saving = Completer<void>();
      final release = Completer<void>();
      store.save = (command) async {
        saving.complete();
        await release.future;
        return store.store.addStoredCommand(command);
      };
      final peer = _Peer(store);
      await peer.next<ReplicationMessageDependency>();
      peer.send(ReplicationMessageCommand(_command('remote', 1)));
      await saving.future;

      final closing = peer.replicator.close();
      release.complete();
      await closing;
      await peer.finished;

      expect(peer.failure, isNull);
      expect(peer.messages.whereType<ReplicationMessageCommandAck>(), isEmpty);
    });

    for (final operation in ['state', 'next IDs', 'command']) {
      test('$operation read failures stop the session', () async {
        final store = _ControlledStore();
        await _append(store.store, 'local');
        final failure = const FormatException('read failure');
        switch (operation) {
          case 'state':
            store.readState = () async => throw failure;
          case 'next IDs':
            store.readNext = (_, _) async => throw failure;
          case 'command':
            store.readCommand = (_) async => throw failure;
        }
        final peer = _Peer(store);
        if (operation != 'state') {
          await peer.next<ReplicationMessageDependency>();
          peer.send(ReplicationMessageDependency(CommandDependency()));
        }

        await peer.finished;

        expect(peer.failure, same(failure));
        expect(store.listeners, 0);
        expect(peer.messages.whereType<ReplicationMessageCommand>(), isEmpty);
      });
    }

    for (final operation in ['add', 'done', 'close']) {
      test('sink $operation failures reach the caller', () async {
        final failure = const FormatException('sink failure');
        late _TestSink sink;
        final peer = _Peer(
          MemoryEventStore(),
          wrapSink: (underlying) {
            sink = _TestSink(underlying);
            if (operation == 'add') sink.addFailure = failure;
            if (operation == 'close') sink.closeFailure = failure;
            return sink;
          },
        );
        if (operation != 'add') {
          await peer.next<ReplicationMessageDependency>();
          if (operation == 'done') {
            sink.completion.completeError(failure);
          } else {
            await peer.replicator.close();
          }
        }

        await peer.finished;

        expect(peer.failure, same(failure));
      });
    }

    test('a replicator cannot run twice', () async {
      final peer = _Peer(MemoryEventStore());
      await peer.next<ReplicationMessageDependency>();

      expect(peer.replicator.run, throwsStateError);
    });

    test('close can be called repeatedly', () async {
      final peer = _Peer(MemoryEventStore());
      await peer.next<ReplicationMessageDependency>();

      await Future.wait([peer.replicator.close(), peer.replicator.close()]);
      await peer.replicator.close();
      await peer.finished;

      expect(peer.failure, isNull);
    });
  });
}

class _Session {
  Object? failure;
  StackTrace? failureStack;
  bool stopped = false;
  late final Future<void> finished;

  void observe(Future<void> session) {
    finished = session.then(
      (_) => stopped = true,
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        failureStack = stackTrace;
        stopped = true;
      },
    );
  }
}

class _Link extends _Session {
  late final InMemoryReplication replication;

  _Link(
    EventStoreReplication first,
    EventStoreReplication second, {
    bool peer1Receives = true,
    bool peer2Receives = true,
  }) {
    replication = InMemoryReplication(
      store1: first,
      store2: second,
      logger: const NoopLogger(),
    );
    observe(
      replication.run(
        peer1Receives: peer1Receives,
        peer2Receives: peer2Receives,
      ),
    );
    addTearDown(() async {
      await replication.close();
      await finished;
    });
  }
}

class _Peer extends _Session {
  final channel = StreamChannelController<ReplicationMessage>();
  final messages = <ReplicationMessage>[];
  late final Replicator replicator;
  Completer<void> _changed = Completer<void>();
  int _index = 0;
  bool _channelClosed = false;

  _Peer(
    EventStoreReplication store, {
    bool receive = true,
    StreamSink<ReplicationMessage> Function(StreamSink<ReplicationMessage>)?
    wrapSink,
  }) {
    final subscription = channel.foreign.stream.listen(
      (message) {
        messages.add(message);
        _notify();
      },
      onDone: () {
        _channelClosed = true;
        _notify();
      },
    );
    replicator = Replicator(
      channel: wrapSink == null
          ? channel.local
          : StreamChannel(channel.local.stream, wrapSink(channel.local.sink)),
      eventStore: store,
      logger: const NoopLogger(),
    );
    observe(replicator.run(receive: receive));
    addTearDown(() async {
      await replicator.close();
      await finished;
      await subscription.cancel();
    });
  }

  void send(ReplicationMessage message) => channel.foreign.sink.add(message);

  void _notify() {
    _changed.complete();
    _changed = Completer<void>();
  }

  Future<T> next<T extends ReplicationMessage>() async {
    while (_index == messages.length) {
      if (_channelClosed) fail('Channel closed before receiving $T: $failure');
      await _changed.future.timeout(const Duration(seconds: 5));
    }
    final message = messages[_index++];
    expect(message, isA<T>());
    return message as T;
  }
}

class _ControlledStore implements EventStoreReplication {
  final store = MemoryEventStore();
  int listeners = 0;
  Future<bool> Function(StoredCommand)? save;
  Future<EventDatabaseState> Function()? readState;
  Future<List<CommandId>> Function(CommandDependency, int)? readNext;
  Future<StoredCommand?> Function(CommandId)? readCommand;

  @override
  Stream<CommandChange> get commandChanges => Stream.multi((controller) {
    listeners++;
    final subscription = store.commandChanges.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () {
      listeners--;
      return subscription.cancel();
    };
  });

  @override
  Future<bool> addStoredCommand(StoredCommand command) =>
      save?.call(command) ?? store.addStoredCommand(command);

  @override
  Future<EventDatabaseState> getState() =>
      readState?.call() ?? store.getState();

  @override
  Future<StoredCommand?> getStoredCommand(CommandId commandId) =>
      readCommand?.call(commandId) ?? store.getStoredCommand(commandId);

  @override
  Future<List<CommandId>> getNextCommandIds(
    CommandDependency dependency,
    int count,
  ) =>
      readNext?.call(dependency, count) ??
      store.getNextCommandIds(dependency, count);
}

class _TestSink implements StreamSink<ReplicationMessage> {
  final StreamSink<ReplicationMessage> underlying;
  final completion = Completer<void>();
  Object? addFailure;
  Object? closeFailure;

  _TestSink(this.underlying) {
    unawaited(
      underlying.done.then<void>(
        (_) {
          if (!completion.isCompleted) completion.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        },
      ),
    );
  }

  @override
  Future<void> get done => completion.future;

  @override
  void add(ReplicationMessage message) {
    final failure = addFailure;
    if (failure != null) throw failure;
    underlying.add(message);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      underlying.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<ReplicationMessage> stream) =>
      underlying.addStream(stream);

  @override
  Future<void> close() async {
    await underlying.close();
    final failure = closeFailure;
    if (failure != null) throw failure;
  }
}

Future<void> _seed(EventStore store, List<StoredCommand> commands) async {
  for (final command in commands) {
    expect(await store.addStoredCommand(command), isTrue);
  }
}

StoredCommand _command(
  String actor,
  int sequence, {
  Map<String, int> dependency = const {},
}) {
  final time = DateTime.utc(2026);
  return StoredCommand(
    commandId: CommandId(actor, sequence),
    dependency: CommandDependency(dependency),
    occuredAt: time,
    events: [
      StoredCommandEvent(
        streamPath: actor,
        encodedEvent: EncodedEvent(
          kind: 'test',
          bytes: Uint8List.fromList([sequence]),
        ),
        occuredAt: time,
      ),
    ],
  );
}

Future<void> _append(EventStore store, String actor) async {
  final time = DateTime.utc(2026);
  await store.saveChanges(
    CommandChanges(
      actor: actor,
      dependency: (await store.getState()).logVersion,
      occuredAt: time,
      locks: [
        StreamLock(
          streamPath: actor,
          originatingStreamVersion: await store.getStreamVersion(actor),
        ),
      ],
      events: [
        EventAppend(
          streamPath: actor,
          encodedEvent: EncodedEvent(
            kind: 'test',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
          occuredAt: time,
        ),
      ],
    ),
  );
}

Future<void> _whenKnown(
  EventStoreReplication store,
  CommandDependency dependency,
) async {
  final updates = StreamController<void>();
  final subscription = store.commandChanges.listen((_) => updates.add(null));
  updates.add(null);
  try {
    await for (final _ in updates.stream) {
      if ((await store.getState()).logVersion.contains(dependency)) return;
    }
  } finally {
    await subscription.cancel();
    await updates.close();
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
