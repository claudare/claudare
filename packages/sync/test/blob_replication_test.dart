import 'dart:async';
import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:sync/sync.dart';
import 'package:test/test.dart';
import 'package:transport/transport.dart';

import 'transport/proxy_transport_test_helper.dart'
    show TestClock, flushMessages;

void main() {
  group('in-memory blob replication', () {
    test('both peers transfer complete bytes independently', () async {
      final first = MemoryEventStore();
      final second = MemoryEventStore();
      final leftBytes = MemoryBlobStore();
      final rightBytes = MemoryBlobStore();
      await _seed(first, ['right']);
      await _seed(second, ['left']);
      await leftBytes.save('left', Uint8List.fromList([0, 127, 128, 255]));
      await rightBytes.save('right', Uint8List(0));
      final link = _Link(first, second, leftBytes, rightBytes);
      await _until(
        () async =>
            await first.getBlobStatus('right') == BlobStatus.available &&
            await second.getBlobStatus('left') == BlobStatus.available,
      );
      expect(await leftBytes.get('right'), isEmpty);
      expect(await rightBytes.get('left'), [0, 127, 128, 255]);
      expect(link.failure, isNull);
    });

    test(
      'commands committed after idle wake downloading immediately',
      () async {
        final first = MemoryEventStore();
        final second = MemoryEventStore();
        final source = MemoryBlobStore();
        final target = MemoryBlobStore();
        final link = _Link(first, second, source, target);
        await flushMessages();
        await source.save('new', Uint8List.fromList([1]));
        await _seed(second, ['new']);
        await _until(
          () async => await second.getBlobStatus('new') == BlobStatus.available,
        );
        expect(await target.get('new'), [1]);
        expect(link.clock.now(), DateTime.utc(2026));
      },
    );

    test('missing earlier blobs do not block later downloads', () async {
      final source = MemoryBlobStore();
      final target = MemoryBlobStore();
      final first = MemoryEventStore();
      final second = MemoryEventStore(eventFetchPageSize: 1);
      await _seed(second, ['missing', 'present']);
      await source.save('present', Uint8List.fromList([2]));
      final link = _Link(first, second, source, target);
      await _until(
        () async =>
            await second.getBlobStatus('present') == BlobStatus.available,
      );
      expect(await second.getBlobStatus('missing'), BlobStatus.pending);
      expect(link.failure, isNull);
      await source.save('missing', Uint8List.fromList([3]));
      await link.clock.elapse(SyncDefaults.blobRetryInterval);
      expect(await second.getBlobStatus('missing'), BlobStatus.available);
      expect(await target.get('missing'), [3]);
    });
  });

  for (final sqlite in [false, true]) {
    test(
      '${sqlite ? 'SQLite' : 'memory'} saves bytes before availability',
      () async {
        final EventStore target;
        final BlobStore bytes;
        if (sqlite) {
          final database = IsolateSqlite();
          await database.openInMemory();
          addTearDown(database.close);
          final eventStore = SqliteEventStore(database, eventFetchPageSize: 1);
          final blobStore = SqliteBlobStore(database);
          await eventStore.migrate();
          await blobStore.migrate();
          target = eventStore;
          bytes = blobStore;
        } else {
          target = MemoryEventStore(eventFetchPageSize: 1);
          bytes = MemoryBlobStore();
        }
        await _seed(target, ['first', 'second']);
        final observed = _Store(target);
        final saved = <String>[];
        observed.mark = (id) async {
          expect(await bytes.get(id), [1, 255]);
          saved.add(id);
          await target.markBlobAvailable(id);
        };
        final peer = _Peer(store: observed, blobs: bytes);
        peer.onMessage = (message) {
          if (message is BlobReplicationMessageRequest) {
            peer.send(
              BlobReplicationMessageData(
                blobId: message.blobId,
                bytes: Uint8List.fromList([1, 255]),
              ),
            );
          }
        };
        await _until(
          () async =>
              await target.getBlobStatus('second') == BlobStatus.available,
        );
        expect(saved, ['first', 'second']);
        expect(observed.cursors, [0, 1, 2]);
      },
    );
  }

  test(
    'new commands scan the tail without retrying old missing IDs early',
    () async {
      final store = MemoryEventStore();
      await _seed(store, ['missing']);
      final peer = _Peer(store: store);
      peer.onMessage = (message) {
        if (message is BlobReplicationMessageRequest) {
          peer.send(BlobReplicationMessageMissing(blobId: message.blobId));
        }
      };
      await flushMessages();
      await _seed(store, ['new'], actor: 'other');
      await flushMessages();
      expect(peer.requests, ['missing', 'new']);
      await peer.clock.elapse(SyncDefaults.blobRetryInterval);
      expect(peer.requests, ['missing', 'new', 'missing', 'new']);
    },
  );

  test('a blob already available before requesting is skipped', () async {
    final store = MemoryEventStore();
    await _seed(store, ['blob']);
    final observed = _Store(store);
    observed.status = (id) async {
      await store.markBlobAvailable(id);
      return BlobStatus.available;
    };
    final peer = _Peer(store: observed);
    await flushMessages();
    expect(peer.requests, isEmpty);
  });

  for (final stage in ['save', 'mark']) {
    test(
      '$stage failure leaves the blob pending for a fresh session',
      () async {
        final store = MemoryEventStore();
        await _seed(store, ['first', 'second']);
        final observed = _Store(store);
        final blobs = _Blobs();
        final failure = Exception('private data');
        if (stage == 'save') blobs.write = (_, _) async => throw failure;
        if (stage == 'mark') observed.mark = (_) async => throw failure;
        final original = _Peer(store: observed, blobs: blobs);
        await flushMessages();
        original.send(
          BlobReplicationMessageData(
            blobId: 'first',
            bytes: Uint8List.fromList([4]),
          ),
        );
        await original.finished;
        expect(original.failure, same(failure));
        expect(await store.getBlobStatus('first'), BlobStatus.pending);
        if (stage == 'mark') expect(await blobs.store.get('first'), [4]);
        blobs.write = null;
        observed.mark = null;
        final replacement = _Peer(store: observed, blobs: blobs);
        await flushMessages();
        expect(replacement.requests, ['first']);
        replacement.send(
          BlobReplicationMessageData(
            blobId: 'first',
            bytes: Uint8List.fromList([4]),
          ),
        );
        await flushMessages();
        expect(await store.getBlobStatus('first'), BlobStatus.available);
        expect(replacement.requests, ['first', 'second']);
        expect(
          original.logger.entries.single.message,
          'Blob replication session failed',
        );
        expect(original.logger.entries.single.error, isNull);
      },
    );
  }

  test('serving proceeds while a download save is blocked', () async {
    final store = MemoryEventStore();
    await _seed(store, ['download']);
    final saving = Completer<void>();
    final blobs = _Blobs()..write = (_, _) => saving.future;
    await blobs.store.save('serve', Uint8List.fromList([9]));
    final peer = _Peer(store: store, blobs: blobs);
    await flushMessages();
    peer.send(
      BlobReplicationMessageData(blobId: 'download', bytes: Uint8List(0)),
    );
    peer.send(const BlobReplicationMessageRequest(blobId: 'serve'));
    await flushMessages();
    expect(peer.messages.whereType<BlobReplicationMessageData>().single.bytes, [
      9,
    ]);
    saving.complete();
    await flushMessages();
  });

  test('downloading proceeds while a serving read is blocked', () async {
    final store = MemoryEventStore();
    await _seed(store, ['download']);
    final reading = Completer<Uint8List?>();
    final blobs = _Blobs()..read = (_) => reading.future;
    final peer = _Peer(store: store, blobs: blobs);
    await flushMessages();
    peer.send(const BlobReplicationMessageRequest(blobId: 'serve'));
    peer.send(
      BlobReplicationMessageData(
        blobId: 'download',
        bytes: Uint8List.fromList([8]),
      ),
    );
    await flushMessages();
    expect(await store.getBlobStatus('download'), BlobStatus.available);
    reading.complete(null);
    await flushMessages();
  });

  for (final referenced in [false, true]) {
    test('serves stored bytes with pending metadata=$referenced', () async {
      final store = MemoryEventStore();
      if (referenced) await _seed(store, ['blob']);
      final blobs = MemoryBlobStore();
      await blobs.save('blob', Uint8List.fromList([7]));
      final peer = _Peer(store: store, blobs: blobs);
      peer.send(const BlobReplicationMessageRequest(blobId: 'blob'));
      await flushMessages();
      expect(
        peer.messages.whereType<BlobReplicationMessageData>().single.bytes,
        [7],
      );
    });
  }

  test(
    'disabled storage responds missing without scanning or timers',
    () async {
      final store = _Store(MemoryEventStore());
      final peer = _Peer(store: store, disabled: true);
      peer.send(const BlobReplicationMessageRequest(blobId: 'absent'));
      await flushMessages();
      expect(peer.messages.single, isA<BlobReplicationMessageMissing>());
      expect(store.cursors, isEmpty);
      expect(peer.clock.activeTimers, 0);
    },
  );

  for (final response in <BlobReplicationMessage>[
    const BlobReplicationMessageMissing(blobId: 'wrong'),
    BlobReplicationMessageData(blobId: 'wrong', bytes: Uint8List(0)),
  ]) {
    for (final pending in [false, true]) {
      test(
        'unexpected ${response.runtimeType} fails with pending=$pending',
        () async {
          final store = MemoryEventStore();
          if (pending) await _seed(store, ['expected']);
          final peer = _Peer(store: store);
          await flushMessages();
          peer.send(response);
          await peer.finished;
          expect(peer.failure, isA<BlobReplicationException>());
        },
      );
    }
  }

  test('overlapping inbound requests fail the protocol', () async {
    final reading = Completer<Uint8List?>();
    final peer = _Peer(blobs: _Blobs()..read = (_) => reading.future);
    peer.send(const BlobReplicationMessageRequest(blobId: 'first'));
    peer.send(const BlobReplicationMessageRequest(blobId: 'second'));
    await peer.finished;
    expect(peer.failure, isA<BlobReplicationException>());
    reading.complete(null);
    await flushMessages();
  });

  test('duplicate data during persistence fails the protocol', () async {
    final store = MemoryEventStore();
    await _seed(store, ['blob']);
    final saving = Completer<void>();
    final blobs = _Blobs();
    blobs.write = (id, bytes) async {
      await saving.future;
      await blobs.store.save(id, bytes);
    };
    final peer = _Peer(store: store, blobs: blobs);
    await flushMessages();
    final data = BlobReplicationMessageData(
      blobId: 'blob',
      bytes: Uint8List(0),
    );
    peer.send(data);
    peer.send(data);
    await peer.finished;
    expect(peer.failure, isA<BlobReplicationException>());
    saving.complete();
    await flushMessages();
  });

  test('remote closure leaves the blob pending and cancels timers', () async {
    final store = MemoryEventStore();
    await _seed(store, ['blob']);
    final peer = _Peer(store: store);
    await flushMessages();
    await peer.channel.foreign.sink.close();
    await peer.finished;
    expect(peer.failure, isNull);
    expect(peer.clock.activeTimers, 0);
    final replacement = _Peer(store: store);
    await flushMessages();
    expect(replacement.requests, ['blob']);
  });

  for (final blocked in ['scan', 'serve']) {
    test('close is prompt with a blocked $blocked operation', () async {
      final store = MemoryEventStore();
      final observed = _Store(store);
      final blobs = _Blobs();
      final gate = Completer<void>();
      if (blocked != 'serve') await _seed(store, ['blob']);
      if (blocked == 'scan') {
        observed.page = (_) async {
          await gate.future;
          return store.getPendingBlobIds(0);
        };
      }
      if (blocked == 'serve') {
        blobs.read = (_) async {
          await gate.future;
          return Uint8List.fromList([3]);
        };
      }
      final peer = _Peer(store: observed, blobs: blobs);
      await flushMessages();
      if (blocked == 'serve') {
        peer.send(const BlobReplicationMessageRequest(blobId: 'blob'));
      }
      await flushMessages();
      final sent = peer.messages.length;
      await peer.worker.close().timeout(const Duration(seconds: 1));
      await peer.finished;
      expect(peer.clock.activeTimers, 0);
      final replacement = _Peer(store: store);
      await flushMessages();
      gate.complete();
      await flushMessages();
      expect(peer.messages, hasLength(sent));
      expect(peer.failure, isNull);
      if (blocked != 'serve') {
        expect(await store.getBlobStatus('blob'), BlobStatus.pending);
        expect(replacement.requests, ['blob']);
      }
    });
  }

  for (final blocked in ['save', 'mark']) {
    test(
      'accepted persistence finishes after closure during $blocked',
      () async {
        final store = MemoryEventStore();
        await _seed(store, ['first', 'second']);
        final observed = _Store(store);
        final blobs = _Blobs();
        final gate = Completer<void>();
        blobs.write = (id, bytes) async {
          if (blocked == 'save') await gate.future;
          await blobs.store.save(id, bytes);
        };
        observed.mark = (id) async {
          if (blocked == 'mark') await gate.future;
          await store.markBlobAvailable(id);
        };
        final peer = _Peer(store: observed, blobs: blobs);
        await flushMessages();
        peer.send(
          BlobReplicationMessageData(
            blobId: 'first',
            bytes: Uint8List.fromList([0, 255]),
          ),
        );
        await flushMessages();
        expect(await store.getBlobStatus('first'), BlobStatus.pending);

        await peer.worker.close().timeout(const Duration(seconds: 1));
        await peer.finished;
        gate.complete();
        await _until(
          () async =>
              await store.getBlobStatus('first') == BlobStatus.available,
        );

        expect(await blobs.store.get('first'), [0, 255]);
        expect(await store.getBlobStatus('second'), BlobStatus.pending);
        expect(peer.requests, ['first']);
        expect(peer.clock.activeTimers, 0);
        expect(peer.failure, isNull);
      },
    );
  }

  for (final sqlite in [false, true]) {
    test(
      '${sqlite ? 'SQLite' : 'memory'} accepts concurrent identical downloads',
      () async {
        final EventStore store;
        final BlobStore blobs;
        if (sqlite) {
          final database = IsolateSqlite();
          await database.openInMemory();
          addTearDown(database.close);
          final events = SqliteEventStore(database);
          final bytes = SqliteBlobStore(database);
          await events.migrate();
          await bytes.migrate();
          store = events;
          blobs = bytes;
        } else {
          store = MemoryEventStore();
          blobs = MemoryBlobStore();
        }
        await _seed(store, ['shared']);
        final observed = _Store(store);
        var marks = 0;
        observed.mark = (id) async {
          await store.markBlobAvailable(id);
          marks++;
        };
        final first = _Peer(store: observed, blobs: blobs);
        final second = _Peer(store: observed, blobs: blobs);
        await _until(
          () async => first.requests.isNotEmpty && second.requests.isNotEmpty,
        );
        final data = BlobReplicationMessageData(
          blobId: 'shared',
          bytes: Uint8List.fromList([5]),
        );
        first.send(data);
        second.send(data);
        await _until(() async => marks == 2);
        expect(await blobs.get('shared'), [5]);
        expect(first.failure, isNull);
        expect(second.failure, isNull);
      },
    );
  }

  for (final operation in ['scan', 'status', 'serve']) {
    test('$operation failure preserves its error and stack trace', () async {
      final store = MemoryEventStore();
      final observed = _Store(store);
      final blobs = _Blobs();
      final failure = Exception('private details');
      final stack = StackTrace.fromString('original storage failure');
      if (operation == 'scan') {
        observed.page = (_) => Future.error(failure, stack);
      }
      if (operation == 'status') {
        await _seed(store, ['blob']);
        observed.status = (_) => Future.error(failure, stack);
      }
      if (operation == 'serve') {
        blobs.read = (_) => Future.error(failure, stack);
      }
      final peer = _Peer(store: observed, blobs: blobs);
      if (operation == 'serve') {
        peer.send(const BlobReplicationMessageRequest(blobId: 'blob'));
      }
      await peer.finished;
      expect(peer.failure, same(failure));
      expect(peer.failureStack.toString(), stack.toString());
      expect(peer.clock.activeTimers, 0);
      expect(peer.logger.entries.single.error, isNull);
    });
  }

  test(
    'transport stream failure closes the worker and preserves pending work',
    () async {
      final store = MemoryEventStore();
      await _seed(store, ['blob']);
      final peer = _Peer(store: store);
      await flushMessages();
      final failure = Exception('transport');
      peer.channel.foreign.sink.addError(failure);
      await peer.finished;
      expect(peer.failure, same(failure));
      expect(await store.getBlobStatus('blob'), BlobStatus.pending);
      expect(peer.clock.activeTimers, 0);
    },
  );

  test('a command arriving during a blocked scan is not missed', () async {
    final store = MemoryEventStore();
    final observed = _Store(store);
    final loading = Completer<PaginatedResult<String>>();
    observed.page = (_) => loading.future;
    final peer = _Peer(store: observed);
    await _seed(store, ['new']);
    observed.page = null;
    loading.complete(const PaginatedResult(data: [], next: null));
    await flushMessages();
    expect(peer.requests, ['new']);
  });

  test('late storage failure does not affect a replacement worker', () async {
    final store = MemoryEventStore();
    await _seed(store, ['blob']);
    final blobs = _Blobs();
    final saving = Completer<void>();
    blobs.write = (_, _) => saving.future;
    final original = _Peer(store: store, blobs: blobs);
    await flushMessages();
    original.send(
      BlobReplicationMessageData(blobId: 'blob', bytes: Uint8List(0)),
    );
    await flushMessages();
    await original.worker.close();
    blobs.write = null;
    final replacement = _Peer(store: store, blobs: blobs);
    await flushMessages();
    saving.completeError(Exception('late failure'));
    await flushMessages();
    replacement.send(
      BlobReplicationMessageData(blobId: 'blob', bytes: Uint8List(0)),
    );
    await flushMessages();
    expect(await store.getBlobStatus('blob'), BlobStatus.available);
    expect(replacement.failure, isNull);
    expect(original.logger.entries, isEmpty);
  });

  test(
    'malformed blob data resets blobs while command replication continues',
    () async {
      final wire = StreamChannelController<String>();
      final left = PeerMultiplexer(wire.local);
      final right = PeerMultiplexer(wire.foreign);
      final store = MemoryEventStore();
      final commands = CommandReplicator(
        channel: left.commands.transform(
          StreamChannelTransformer.fromCodec(
            const CommandReplicationMessageCodec(),
          ),
        ),
        eventStore: store,
        logger: const NoopLogger(),
      );
      final blobs = BlobReplicator(
        channel: left.blobs.transform(
          StreamChannelTransformer.fromCodec(
            const BlobReplicationMessageCodec(),
          ),
        ),
        eventStore: store,
        blobStore: MemoryBlobStore(),
        logger: const NoopLogger(),
      );
      final commandMessages = <CommandReplicationMessage>[];
      final commandSession = right.commands;
      right.commands
          .transform(
            StreamChannelTransformer.fromCodec(
              const CommandReplicationMessageCodec(),
            ),
          )
          .stream
          .listen(commandMessages.add);
      var commandsStopped = false;
      final runningCommands = commands.run().whenComplete(
        () => commandsStopped = true,
      );
      final failedBlobs = expectLater(blobs.run(), throwsFormatException);
      addTearDown(() async {
        await left.close();
        await right.close();
        await commands.close();
        await blobs.close();
        await runningCommands;
      });
      await flushMessages();
      right.blobs.sink.add('invalid JSON');
      await failedBlobs;
      expect(right.commands, same(commandSession));
      expect(commandsStopped, isFalse);
      final command = _command(['pending']);
      right.commands.sink.add(
        const CommandReplicationMessageCodec().encode(
          CommandReplicationMessageCommand(command),
        ),
      );
      await flushMessages();
      expect(commandMessages.last, isA<CommandReplicationMessageCommandAck>());
      expect(await store.getBlobStatus('pending'), BlobStatus.pending);
      expect(commandsStopped, isFalse);
    },
  );

  for (final invalid in [Duration.zero, const Duration(seconds: -1)]) {
    test('rejects retryInterval=$invalid', () {
      final channel = StreamChannelController<BlobReplicationMessage>();
      expect(
        () => BlobReplicator(
          channel: channel.local,
          eventStore: MemoryEventStore(),
          blobStore: null,
          logger: const NoopLogger(),
          retryInterval: invalid,
        ),
        throwsArgumentError,
      );
    });
  }

  test('run is single-use and repeated closure is safe', () async {
    final peer = _Peer();
    expect(peer.worker.run, throwsStateError);
    await peer.worker.close();
    await peer.worker.close();
    await peer.finished;
    expect(peer.failure, isNull);
  });
}

class _Peer {
  final channel = StreamChannelController<BlobReplicationMessage>();
  final clock = TestClock();
  final logger = RecordingLogger();
  final messages = <BlobReplicationMessage>[];
  late final BlobReplicator worker;
  late final StreamSubscription<BlobReplicationMessage> _remote;
  late final Future<void> finished;
  Object? failure;
  StackTrace? failureStack;
  void Function(BlobReplicationMessage)? onMessage;

  _Peer({
    EventStoreReplication? store,
    BlobStore? blobs,
    bool disabled = false,
  }) {
    _remote = channel.foreign.stream.listen((message) {
      messages.add(message);
      onMessage?.call(message);
    });
    worker = BlobReplicator(
      channel: channel.local,
      eventStore: store ?? MemoryEventStore(),
      blobStore: disabled ? null : blobs ?? MemoryBlobStore(),
      logger: logger,
      timerFactory: clock.schedule,
    );
    finished = worker.run().then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
      },
    );
    addTearDown(() async {
      await worker.close();
      await finished;
      await _remote.cancel();
    });
  }

  List<String> get requests => messages
      .whereType<BlobReplicationMessageRequest>()
      .map((message) => message.blobId)
      .toList();
  void send(BlobReplicationMessage message) =>
      channel.foreign.sink.add(message);
}

class _Link {
  final clock = TestClock();
  late final InMemoryBlobReplication replication;
  late final Future<void> finished;
  Object? failure;

  _Link(
    EventStoreReplication first,
    EventStoreReplication second,
    BlobStore? firstBlobs,
    BlobStore? secondBlobs,
  ) {
    replication = InMemoryBlobReplication(
      store1: first,
      store2: second,
      blobStore1: firstBlobs,
      blobStore2: secondBlobs,
      logger: const NoopLogger(),
      timerFactory: clock.schedule,
    );
    finished = replication.run().then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure = error;
      },
    );
    addTearDown(() async {
      await replication.close();
      await finished;
    });
  }
}

class _Blobs implements BlobStore {
  final store = MemoryBlobStore();
  Future<Uint8List?> Function(String)? read;
  Future<void> Function(String, Uint8List)? write;

  @override
  Future<Uint8List?> get(String id) => read?.call(id) ?? store.get(id);
  @override
  Future<void> save(String id, Uint8List bytes) =>
      write?.call(id, bytes) ?? store.save(id, bytes);
}

class _Store implements EventStoreReplication {
  final EventStoreReplication store;
  final cursors = <int>[];
  Future<PaginatedResult<String>> Function(int)? page;
  Future<BlobStatus?> Function(String)? status;
  Future<void> Function(String)? mark;
  _Store(this.store);

  @override
  Stream<CommandChange> get commandChanges => store.commandChanges;
  @override
  Future<PaginatedResult<String>> getPendingBlobIds(int cursor) {
    cursors.add(cursor);
    return page?.call(cursor) ?? store.getPendingBlobIds(cursor);
  }

  @override
  Future<BlobStatus?> getBlobStatus(String id) =>
      status?.call(id) ?? store.getBlobStatus(id);
  @override
  Future<void> markBlobAvailable(String id) =>
      mark?.call(id) ?? store.markBlobAvailable(id);
  @override
  Future<EventDatabaseState> getState() => store.getState();
  @override
  Future<bool> addStoredCommand(StoredCommand command) =>
      store.addStoredCommand(command);
  @override
  Future<StoredCommand?> getStoredCommand(CommandId id) =>
      store.getStoredCommand(id);
  @override
  Future<List<CommandId>> getNextCommandIds(
    CommandDependency dependency,
    int count,
  ) => store.getNextCommandIds(dependency, count);
}

Future<void> _seed(
  EventStoreReplication store,
  List<String> ids, {
  String actor = 'remote',
}) async {
  expect(await store.addStoredCommand(_command(ids, actor: actor)), isTrue);
}

StoredCommand _command(List<String> ids, {String actor = 'remote'}) =>
    StoredCommand(
      commandId: CommandId(actor, 1),
      dependency: CommandDependency(),
      occuredAt: DateTime.utc(2026),
      blobIds: ids,
      events: [
        StoredCommandEvent(
          streamPath: actor,
          encodedEvent: EncodedEvent(kind: 'test', bytes: Uint8List(0)),
          occuredAt: DateTime.utc(2026),
        ),
      ],
    );

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Blob replication did not finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await flushMessages();
}
