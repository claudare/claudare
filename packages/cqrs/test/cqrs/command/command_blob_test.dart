import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:cqrs/src/cqrs/command/command_changes.dart';
import 'package:id_generator/id_generator.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  CommandTester tester({
    BlobStore? blobs,
    EventStore? events,
    IdGenerator? ids,
  }) => CommandTester(
    timeProvider: FakeTimeProviderStatic.zero(),
    blobStore: blobs,
    eventStore: events,
    idGenerator: ids,
  )..registerEvent(const _Codec());

  test('records writes in registration order with deterministic IDs', () async {
    final run = tester();
    await run.run(
      _Command((ctx) async {
        final first = ctx.generateId();
        final second = ctx.generateId();
        ctx.saveBlob(second, Uint8List.fromList([2]));
        ctx.saveBlob(first, Uint8List.fromList([1]));
        await _emit(ctx, first);
      }),
    );
    expect(run.getWrittenBlobs().map((blob) => blob.blobId), ['2', '1']);
    expect(await run.getWrittenEvents<String>('stream'), ['1']);
  });

  test('uses an injected ID generator', () async {
    final ids = IdGeneratorSequential()..generateId();
    final run = tester(ids: ids);
    await run.run(
      _Command((ctx) async {
        final id = ctx.generateId();
        ctx.saveBlob(id, Uint8List(0));
        await _emit(ctx, id);
      }),
    );
    expect(run.getWrittenBlobs().single.blobId, '2');
  });

  test('snapshots bytes at registration', () async {
    final data = Uint8List.fromList([1]);
    final run = tester();
    await run.run(
      _Command((ctx) async {
        ctx.saveBlob('blob', data);
        data[0] = 9;
        await _emit(ctx);
      }),
    );
    expect(run.getWrittenBlobs().single.data, [1]);
    expect(
      () => run.getWrittenBlobs().single.data[0] = 7,
      throwsUnsupportedError,
    );
    expect(run.getWrittenBlobs().single.data, [1]);
  });

  test('rejects duplicate registration before persistence', () async {
    final run = tester();
    await expectLater(
      run.run(
        _Command((ctx) async {
          ctx.saveBlob('blob', Uint8List(0));
          ctx.saveBlob('blob', Uint8List(0));
        }),
      ),
      throwsStateError,
    );
    expect(run.getWrittenBlobs(), isEmpty);
  });

  test('rejects blobs without events before persistence', () async {
    final events = MemoryEventStore();
    final run = tester(events: events);
    await expectLater(
      run.run(
        _Command((ctx) async {
          ctx.saveBlob('blob', Uint8List(0));
        }),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          'Exception: Changes are not valid',
        ),
      ),
    );
    expect(run.getWrittenBlobs(), isEmpty);
    expect((await events.getState()).lastCommandLogPosition, isNull);
  });

  test('rejects writes after the context is sealed', () async {
    late CommandContextApi context;
    final run = tester();
    await run.run(_Command((ctx) async => context = ctx));
    expect(() => context.saveBlob('blob', Uint8List(0)), throwsStateError);
  });

  test('requires execution before inspecting writes', () {
    expect(() => tester().getWrittenBlobs(), throwsStateError);
  });

  test('saves in parallel and waits for all blobs before events', () async {
    final blobs = _GatedBlobStore();
    final events = MemoryEventStore();
    final run = tester(blobs: blobs, events: events);
    final execution = run.run(
      _Command((ctx) async {
        ctx.saveBlob('first', Uint8List(0));
        ctx.saveBlob('second', Uint8List(0));
        await _emit(ctx);
      }),
    );
    await blobs.started.future;
    expect((await events.getState()).lastCommandLogPosition, isNull);
    expect(blobs.attempts, ['first', 'second']);
    blobs.release['second']!.complete();
    await blobs.completed['second']!.future;
    expect((await events.getState()).lastCommandLogPosition, isNull);
    blobs.release['first']!.complete();
    await execution;
    expect(run.getWrittenBlobs().map((blob) => blob.blobId), [
      'first',
      'second',
    ]);
    expect(
      (await events.getStoredCommand(const CommandId('test-actor', 1)))!
          .blobIds,
      ['first', 'second'],
    );
  });

  test('blob failure prevents events and retains successful writes', () async {
    final failure = Exception('save failed');
    final blobs = _FailingBlobStore(failure);
    final events = MemoryEventStore();
    final run = tester(blobs: blobs, events: events);
    await expectLater(
      run.run(
        _Command((ctx) async {
          ctx.saveBlob('first', Uint8List.fromList([1]));
          ctx.saveBlob('fail', Uint8List(0));
          ctx.saveBlob('last', Uint8List(0));
          await _emit(ctx);
        }),
      ),
      throwsA(same(failure)),
    );
    expect(run.getWrittenBlobs().map((blob) => blob.blobId), ['first', 'last']);
    expect(await blobs.get('first'), [1]);
    expect(await blobs.get('last'), isEmpty);
    expect((await events.getState()).lastCommandLogPosition, isNull);
  });

  test('waits for in-flight writes after a blob failure', () async {
    final blobs = _GatedBlobStore();
    final events = MemoryEventStore();
    final run = tester(blobs: blobs, events: events);
    final failure = Exception('save failed');
    var finished = false;
    final execution = run
        .run(
          _Command((ctx) async {
            ctx.saveBlob('first', Uint8List(0));
            ctx.saveBlob('second', Uint8List(0));
            await _emit(ctx);
          }),
        )
        .whenComplete(() => finished = true);
    final checked = expectLater(execution, throwsA(same(failure)));
    await blobs.started.future;
    blobs.release['second']!.completeError(failure);
    await blobs.completed['second']!.future;
    expect(finished, isFalse);
    blobs.release['first']!.complete();
    await checked;
    expect(run.getWrittenBlobs().single.blobId, 'first');
    expect((await events.getState()).lastCommandLogPosition, isNull);
  });

  for (final failure in [
    Exception('event save failed'),
    ConcurrencyProblem(),
  ]) {
    test('event failure retains blobs: ${failure.runtimeType}', () async {
      final blobs = MemoryBlobStore();
      final run = tester(blobs: blobs, events: _FailingEventStore(failure));
      await expectLater(
        run.run(
          _Command((ctx) async {
            ctx.saveBlob('blob', Uint8List.fromList([1]));
            await _emit(ctx);
          }),
        ),
        throwsA(same(failure)),
      );
      expect(await blobs.get('blob'), [1]);
      expect(run.getWrittenBlobs().single.blobId, 'blob');
    });
  }

  test('handler failure does not persist registered blobs', () async {
    final run = tester();
    final failure = Exception('handler failed');
    await expectLater(
      run.run(
        _Command((ctx) async {
          ctx.saveBlob('blob', Uint8List(0));
          await _emit(ctx);
          throw failure;
        }),
      ),
      throwsA(same(failure)),
    );
    expect(run.getWrittenBlobs(), isEmpty);
  });
}

Future<void> _emit(CommandContextApi ctx, [String event = 'event']) async {
  final stream = ctx.stream<String>('stream');
  await stream.mustNotExist();
  stream.append(event);
}

class _Command implements Command {
  final Future<void> Function(CommandContextApi) callback;
  _Command(this.callback);
  @override
  Future<void> handle(CommandContextApi ctx) => callback(ctx);
}

class _Codec implements EventCodec<String> {
  const _Codec();
  @override
  String get kind => 'text';
  @override
  Uint8List toBytes(String event) => Uint8List.fromList(utf8.encode(event));
  @override
  String fromBytes(Uint8List bytes) => utf8.decode(bytes);
}

class _GatedBlobStore extends MemoryBlobStore {
  final started = Completer<void>();
  final release = {'first': Completer<void>(), 'second': Completer<void>()};
  final completed = {'first': Completer<void>(), 'second': Completer<void>()};
  final List<String> attempts = [];
  @override
  Future<void> save(String blobId, Uint8List data) async {
    attempts.add(blobId);
    if (attempts.length == 2) started.complete();
    try {
      await release[blobId]!.future;
      await super.save(blobId, data);
    } finally {
      completed[blobId]!.complete();
    }
  }
}

class _FailingBlobStore extends MemoryBlobStore {
  final Exception failure;
  _FailingBlobStore(this.failure);
  @override
  Future<void> save(String blobId, Uint8List data) async {
    if (blobId == 'fail') throw failure;
    await super.save(blobId, data);
  }
}

class _FailingEventStore extends MemoryEventStore {
  final Exception failure;
  _FailingEventStore(this.failure);
  @override
  Future<void> saveChanges(CommandChanges changes) async => throw failure;
}
