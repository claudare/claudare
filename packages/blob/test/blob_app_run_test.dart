import 'dart:async';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in eventStoreTestBackends) {
    group('${backend.name} BlobApp runtime', () {
      late EventStore events;
      late CqrsTestRuntime runtime;
      late _ObservedStore store;
      late BlobApp app;

      setUp(() async {
        final session = await backend.open();
        addTearDown(session.close);
        events = session.store;
        runtime = CqrsTestRuntime(eventStore: events);
        store = _ObservedStore();
        app = BlobApp(runtime: runtime, blobStore: store);
      });

      Future<void> seed(String id) async {
        await store.save(id, Uint8List.fromList([1]));
        await runtime.seedEvents([
          TestEvent(
            actor: 'actor',
            stream: '_blob/$id',
            event: const BlobCreated(),
            occuredAt: DateTime.utc(2026),
          ),
        ]);
      }

      Future<void> delete(String id) =>
          runtime.execute(_Command((ctx) => app.delete(ctx, id)));

      void start() {
        final running = app.run();
        addTearDown(() async {
          await app.close();
          await running;
        });
      }

      test('erases bytes only after a local deletion commits', () async {
        await seed('id');
        start();
        final staged = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });

        final deleting = runtime.execute(
          _Command((ctx) async {
            await app.delete(ctx, 'id');
            staged.complete();
            await release.future;
          }),
        );
        await staged.future;
        expect(await store.get('id'), [1]);
        expect(store.deleteCalls, isEmpty);

        release.complete();
        await deleting;
        await store.deleted('id');

        expect(await app.get('id'), isNull);
      });

      test('catches up existing deletions across log pages', () async {
        for (final id in ['one', 'two', 'three']) {
          await seed(id);
          await delete(id);
        }

        start();
        await Future.wait(['one', 'two', 'three'].map(store.deleted));

        expect(store.deleteCalls, ['one', 'two', 'three']);
        for (final id in ['one', 'two', 'three']) {
          expect(await store.get(id), isNull);
        }
      });

      for (final kind in ['active', 'orphan', 'erased', 'other stream']) {
        test('preserves bytes for $kind', () async {
          await store.save('kept', Uint8List.fromList([1]));
          if (kind == 'active') {
            await seed('kept');
          } else if (kind != 'orphan') {
            await events.addStoredCommand(
              _storedEvent(
                kind == 'erased' ? '_blob/kept' : 'other/kept',
                kind == 'erased'
                    ? EncodedEvent.eventErased()
                    : EncodedEvent.streamDeleted(),
              ),
            );
          }
          await seed('deleted');
          await delete('deleted');

          start();
          await store.deleted('deleted');

          expect(await app.get('kept'), [1]);
          expect(store.deleteCalls, ['deleted']);
        });
      }

      test('erases bytes after a remote deletion commits', () async {
        await seed('id');
        start();

        expect(
          await events.addStoredCommand(
            _storedEvent('_blob/id', EncodedEvent.streamDeleted()),
          ),
          isTrue,
        );
        await store.deleted('id');

        expect(await app.get('id'), isNull);
      });

      test('failed commands leave bytes live', () async {
        await seed('kept');
        await seed('deleted');
        start();

        await expectLater(
          runtime.execute(
            _Command((ctx) async {
              await app.delete(ctx, 'kept');
              throw Exception('command failed');
            }),
          ),
          throwsException,
        );
        await delete('deleted');
        await store.deleted('deleted');

        expect(await app.get('kept'), [1]);
        expect(store.deleteCalls, ['deleted']);
      });

      test('processes changes arriving during deletion in order', () async {
        await seed('one');
        await seed('two');
        await seed('three');
        await delete('one');
        final started = Completer<void>();
        final release = Completer<void>();
        store.beforeDelete = (id) async {
          if (id == 'one') {
            started.complete();
            await release.future;
          }
        };
        start();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        await started.future;

        await delete('two');
        await delete('three');
        expect(store.deleteCalls, ['one']);
        release.complete();
        await store.deleted('three');
        await app.close();

        expect(store.deleteCalls, ['one', 'two', 'three']);
      });

      test(
        'close waits for the active deletion and stops later work',
        () async {
          await seed('one');
          await seed('two');
          final started = Completer<void>();
          final release = Completer<void>();
          store.beforeDelete = (_) async {
            started.complete();
            await release.future;
          };
          start();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          await delete('one');
          await started.future;

          var closed = false;
          final closing = app.close().then((_) => closed = true);
          await delete('two');
          expect(closed, isFalse);
          release.complete();
          await closing;

          expect(await app.get('one'), isNull);
          expect(await app.get('two'), [1]);
          expect(store.deleteCalls, ['one']);
        },
      );

      test('reports deletion failures through run and close', () async {
        await seed('id');
        await delete('id');
        final failure = Exception('delete failed');
        store.beforeDelete = (_) async => throw failure;

        await expectLater(app.run(), throwsA(same(failure)));
        await expectLater(app.close(), throwsA(same(failure)));

        expect(await app.get('id'), [1]);
      });

      test('rejects a second run', () async {
        start();

        expect(app.run, throwsStateError);
      });
    });
  }

  test('reports log read failures through run and close', () async {
    final events = _FailingEventStore();
    final app = BlobApp(
      runtime: CqrsTestRuntime(eventStore: events),
      blobStore: MemoryBlobStore(),
    );

    await expectLater(app.run(), throwsA(same(events.failure)));
    await expectLater(app.close(), throwsA(same(events.failure)));
  });
}

final class _Command implements Command {
  final Future<void> Function(CommandContextApi) _handle;

  _Command(this._handle);

  @override
  Future<void> handle(CommandContextApi ctx) => _handle(ctx);
}

StoredCommand _storedEvent(String stream, EncodedEvent event) => StoredCommand(
  commandId: const CommandId('remote', 1),
  dependency: CommandDependency(),
  occuredAt: DateTime.utc(2026),
  events: [
    StoredCommandEvent(
      streamPath: stream,
      encodedEvent: event,
      occuredAt: DateTime.utc(2026),
    ),
  ],
);

final class _ObservedStore extends MemoryBlobStore {
  final deleteCalls = <String>[];
  final _deleted = <String, Completer<void>>{};
  Future<void> Function(String)? beforeDelete;

  Future<void> deleted(String id) =>
      _deleted.putIfAbsent(id, Completer<void>.new).future;

  @override
  Future<List<String>> listIds() =>
      throw StateError('Runtime deletion must not enumerate stored blobs');

  @override
  Future<void> delete(String blobId) async {
    deleteCalls.add(blobId);
    await beforeDelete?.call(blobId);
    await super.delete(blobId);
    final done = _deleted.putIfAbsent(blobId, Completer<void>.new);
    if (!done.isCompleted) done.complete();
  }
}

final class _FailingEventStore extends MemoryEventStore {
  final failure = Exception('read failed');

  @override
  Future<Never> getLogEvents(LogFilter filter, int fromPosition) async =>
      throw failure;
}
