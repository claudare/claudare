import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';

void main() {
  late CqrsTestRuntime runtime;
  late BlobApp app;
  late MemoryBlobStore store;

  setUp(() {
    runtime = CqrsTestRuntime();
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

    final events = await runtime.streamReader('_blob/blob-id').scan().toList();
    expect(events, hasLength(1));
    expect(
      runtime.eventRegistry.decode<Object>(events.single.encodedEvent),
      isA<BlobCreated>(),
    );
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

  test('identification failure leaves blobs untouched', () async {
    await store.save('orphan', Uint8List.fromList([1]));
    final failing = BlobApp(
      runtime: CqrsTestRuntime(),
      blobStore: _FailingStore(store, failList: true),
    );

    await expectLater(failing.optimize(), throwsException);
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
