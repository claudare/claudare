import 'dart:async';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:blob/src/blobs_projection.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';

void main() {
  late CqrsTestRuntime runtime;
  late MemoryEventStore eventStore;
  late BlobApp app;
  late MemoryBlobStore store;

  setUp(() {
    eventStore = MemoryEventStore();
    runtime = CqrsTestRuntime(eventStore: eventStore);
    store = MemoryBlobStore();
    app = BlobApp(
      runtime: runtime,
      blobStore: store,
      idGenerator: IdGeneratorStatic('blob-id'),
    );
  });

  test('saves and retrieves bytes using the generated ID', () async {
    final command = _SaveBlob(app, Uint8List.fromList([1, 2]));

    await runtime.execute(command);

    expect(command.id, 'blob-id');
    expect(await app.get(command.id), [1, 2]);
  });

  test('creates an event on the blob stream', () async {
    await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));

    final events = await LogPlayer(eventStore)
        .streamReader('_blob/blob-id')
        .toList();
    expect(events, hasLength(1));
    expect(
      runtime.eventRegistry.decode<Object>(events.single.encodedEvent),
      isA<BlobCreated>(),
    );
  });

  test('deletes the blob stream with one retained marker', () async {
    await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));

    await runtime.execute(_DeleteBlob(app, 'blob-id'));

    final info = await eventStore.getStreamInfo('_blob/blob-id');
    final events = await LogPlayer(eventStore)
        .streamReader('_blob/blob-id')
        .toList();
    expect(info.isDeleted, isTrue);
    expect(events.map((event) => event.encodedEvent.kind), [
      SystemEventKinds.eventErased,
      SystemEventKinds.streamDeleted,
    ]);
  });

  test('keeps bytes until optimize runs when not running', () async {
    await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));
    final command = _PausedDelete(app, 'blob-id');

    final deletion = runtime.execute(command);
    await command.staged.future;
    expect(await store.get('blob-id'), [1]);

    command.release.complete();
    await deletion;
    expect(await store.get('blob-id'), [1]);

    await app.optimize();
    expect(await store.get('blob-id'), isNull);
  });

  test('failed deletion leaves the stream and bytes live', () async {
    await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));

    await expectLater(
      runtime.execute(_FailAfterDelete(app, 'blob-id')),
      throwsException,
    );
    expect(
      (await eventStore.getStreamInfo('_blob/blob-id')).isDeleted,
      isFalse,
    );

    await app.optimize();
    expect(await store.get('blob-id'), [1]);
  });

  test('blob state tracks active IDs and deleted tombstones', () async {
    await runtime.seedEvents([
      TestEvent(
        actor: 'actor',
        stream: '_blob/active',
        event: const BlobCreated(),
        occuredAt: DateTime.utc(2026),
      ),
      TestEvent(
        actor: 'actor',
        stream: '_blob/deleted',
        event: const BlobCreated(),
        occuredAt: DateTime.utc(2026),
      ),
    ]);
    await runtime.execute(_DeleteBlob(app, 'deleted'));

    final state = await runtime.resolveProjection(BlobsProjection());

    expect(state.activeIds, {'active'});
    expect(state.deletedIds, {'deleted'});
    final deletedEvents = await LogPlayer(eventStore)
        .streamReader('_blob/deleted')
        .toList();
    expect(deletedEvents.first.encodedEvent.isEventErased, isTrue);
  });

  test(
    'optimize removes failed writes and preserves committed blobs',
    () async {
      await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));
      final failedApp = BlobApp(
        runtime: CqrsTestRuntime(),
        blobStore: store,
        idGenerator: IdGeneratorStatic('orphan'),
      );
      await expectLater(
        runtime.execute(_FailAfterSave(failedApp)),
        throwsException,
      );

      await app.optimize();

      expect(await store.listIds(), ['blob-id']);
      expect(await app.get('blob-id'), [1]);
    },
  );

  test('listing failure leaves blobs untouched', () async {
    await store.save('orphan', Uint8List.fromList([1]));
    final failing = BlobApp(
      runtime: CqrsTestRuntime(),
      blobStore: _FailingStore(store, failList: true),
    );

    await expectLater(failing.optimize(), throwsException);
    expect(await store.get('orphan'), [1]);
  });

  test('resolution failure leaves blobs untouched', () async {
    await store.save('orphan', Uint8List.fromList([1]));
    await eventStore.addStoredCommand(
      StoredCommand(
        commandId: const CommandId('other', 1),
        dependency: CommandDependency(),
        occuredAt: DateTime.utc(2026),
        events: [
          StoredCommandEvent(
            streamPath: '_blob/unknown',
            encodedEvent: EncodedEvent(kind: 'unknown', bytes: Uint8List(0)),
            occuredAt: DateTime.utc(2026),
          ),
        ],
      ),
    );

    await expectLater(app.optimize(), throwsException);
    expect(await store.get('orphan'), [1]);
  });

  test('deletion failure propagates', () async {
    await store.save('orphan', Uint8List.fromList([1]));
    final failing = BlobApp(
      runtime: CqrsTestRuntime(),
      blobStore: _FailingStore(store),
    );

    await expectLater(failing.optimize(), throwsException);
  });

  test('events in other streams do not preserve blobs', () async {
    await store.save('orphan', Uint8List.fromList([1]));
    await runtime.seedEvents([
      TestEvent(
        actor: 'actor',
        stream: 'other/orphan',
        event: const BlobCreated(),
        occuredAt: DateTime.utc(2026),
      ),
    ]);

    await app.optimize();
    expect(await store.get('orphan'), isNull);
  });

  test('optimize preserves active blobs and deletes unused bytes', () async {
    await runtime.execute(_SaveBlob(app, Uint8List.fromList([1])));
    await runtime.seedEvents([
      TestEvent(
        actor: 'actor',
        stream: '_blob/deleted',
        event: const BlobCreated(),
        occuredAt: DateTime.utc(2026),
      ),
    ]);
    await store.save('deleted', Uint8List.fromList([2]));
    await store.save('orphan', Uint8List.fromList([3]));
    await runtime.execute(_DeleteBlob(app, 'deleted'));

    await app.optimize();

    expect(await store.listIds(), ['blob-id']);
    expect(await store.get('blob-id'), [1]);
    expect(await store.get('deleted'), isNull);
    expect(await store.get('orphan'), isNull);
  });
}

final class _FailingStore implements BlobStore {
  @override
  Stream<String> get availableBlobs => store.availableBlobs;

  final BlobStore store;
  final bool failList;
  _FailingStore(this.store, {this.failList = false});

  @override
  Future<List<String>> listIds() async {
    if (failList) throw Exception('list failed');
    return store.listIds();
  }

  @override
  Future<void> delete(String id) async => throw Exception('delete failed');

  @override
  Future<Uint8List?> get(String id) => store.get(id);

  @override
  Future<void> save(String id, Uint8List data) => store.save(id, data);
}

final class _FailAfterSave implements Command {
  final BlobApp app;
  _FailAfterSave(this.app);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    await app.save(ctx, Uint8List.fromList([2]));
    throw Exception('command failed');
  }
}

final class _DeleteBlob implements Command {
  final BlobApp app;
  final String id;

  _DeleteBlob(this.app, this.id);

  @override
  Future<void> handle(CommandContextApi ctx) => app.delete(ctx, id);
}

final class _FailAfterDelete implements Command {
  final BlobApp app;
  final String id;

  _FailAfterDelete(this.app, this.id);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    await app.delete(ctx, id);
    throw Exception('command failed');
  }
}

final class _PausedDelete implements Command {
  final BlobApp app;
  final String id;
  final staged = Completer<void>();
  final release = Completer<void>();

  _PausedDelete(this.app, this.id);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    await app.delete(ctx, id);
    staged.complete();
    await release.future;
  }
}

final class _SaveBlob implements Command {
  final BlobApp app;
  final Uint8List data;
  late String id;

  _SaveBlob(this.app, this.data);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    id = await app.save(ctx, data);
  }
}
