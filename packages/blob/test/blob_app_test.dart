import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:blob/src/blob_index_projection.dart';
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
    runtime = CqrsTestRuntime(
      eventStore: eventStore,
      idGenerator: IdGeneratorStatic('blob-id'),
    );
    store = MemoryBlobStore();
    app = BlobApp(runtime: runtime, blobStore: store);
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

    final state = await runtime.resolveProjection(BlobIndexProjection());

    expect(state.activeIds, {'active'});
    expect(state.deletedIds, {'deleted'});
    final deletedEvents = await LogPlayer(eventStore)
        .streamReader('_blob/deleted')
        .toList();
    expect(deletedEvents.first.encodedEvent.isEventErased, isTrue);
  });
}

final class _DeleteBlob implements Command {
  final BlobApp app;
  final String id;

  _DeleteBlob(this.app, this.id);

  @override
  Future<void> handle(CommandContextApi ctx) => app.integrate(ctx).delete(id);
}

final class _FailAfterDelete implements Command {
  final BlobApp app;
  final String id;

  _FailAfterDelete(this.app, this.id);

  @override
  Future<void> handle(CommandContextApi ctx) async {
    await app.integrate(ctx).delete(id);
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
    id = await app.integrate(ctx).save(data);
  }
}
