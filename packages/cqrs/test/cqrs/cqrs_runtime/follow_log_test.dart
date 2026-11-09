import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

import 'projection_test_support.dart';

void main() {
  late ControlledMemoryEventStore store;
  late LogPlayer logPlayer;

  setUp(() {
    store = ControlledMemoryEventStore();
    logPlayer = LogPlayer(store);
    addTearDown(store.closeChanges);
  });

  StreamIterator<StoredEvent> iterate({
    LogFilter filter = const LogFilter.all(),
    int fromPosition = 0,
    List<AsyncGate> gates = const [],
    void Function()? caughtUp,
  }) {
    final iterator = StreamIterator(
      logPlayer.followLog(
        filter,
        fromPosition: fromPosition,
        caughtUp: caughtUp,
      ),
    );
    addTearDown(() async {
      for (final gate in gates) {
        gate.release();
      }
      await iterator.cancel();
    });
    return iterator;
  }

  test('replays existing events in log order from the beginning', () async {
    for (var index = 0; index < 3; index++) {
      await appendProjectionEvent(store, '$index');
    }
    final iterator = iterate();

    for (var position = 0; position < 3; position++) {
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.position, position);
    }
  });

  test('starts at the inclusive supplied log position', () async {
    for (var index = 0; index < 3; index++) {
      await appendProjectionEvent(store, '$index');
    }
    final iterator = iterate(fromPosition: 1);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.position, 1);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.position, 2);
  });

  for (final (name, filter, positions) in [
    ('exact', const LogFilter.exact('notes/one'), [0, 3]),
    ('prefix', const LogFilter.startsWith('notes/'), [0, 2, 3]),
    ('all', const LogFilter.all(), [0, 1, 2, 3]),
  ]) {
    test('replays only events matching the $name filter', () async {
      for (final path in ['notes/one', 'other', 'notes/two', 'notes/one']) {
        await appendProjectionEvent(store, path, path: path);
      }
      final iterator = iterate(filter: filter);

      for (final position in positions) {
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current.position, position);
      }
      final closing = store.closeChanges();
      expect(await iterator.moveNext(), isFalse);
      await closing;
    });
  }

  test('ignores changes outside its filter while following the log', () async {
    final catchUps = CallSignal();
    final iterator = iterate(
      filter: const LogFilter.exact('notes/one'),
      caughtUp: catchUps.record,
    );
    final next = iterator.moveNext();
    await catchUps.waitFor(1);

    await appendProjectionEvent(store, 'ignored', path: 'other');
    await appendProjectionEvent(store, 'matching');

    expect(await next, isTrue);
    expect(iterator.current.position, 1);
    expect(iterator.current.streamPath, 'notes/one');
  });

  test('delivers events committed during initial replay', () async {
    await appendProjectionEvent(store, 'existing');
    final gate = AsyncGate();
    store.afterRead = (_) => gate.wait();
    final iterator = iterate(gates: [gate]);
    final first = iterator.moveNext();
    await gate.entered.future;
    await appendProjectionEvent(store, 'concurrent');
    store.afterRead = null;
    gate.release();

    expect(await first, isTrue);
    expect(iterator.current.position, 0);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.position, 1);
  });

  test('delivers commits accumulated while paused once in log order', () async {
    await appendProjectionEvent(store, 'first');
    final iterator = iterate();
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.position, 0);

    for (var index = 1; index <= 3; index++) {
      await appendProjectionEvent(store, '$index');
    }
    for (var index = 0; index < 10; index++) {
      store.notify('notes/one');
    }

    for (var position = 1; position <= 3; position++) {
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.position, position);
    }
    final closing = store.closeChanges();
    expect(await iterator.moveNext(), isFalse);
    await closing;
  });

  test('preserves erased records and stream deletion markers', () async {
    await appendProjectionEvent(store, 'erased');
    await appendProjectionEvent(
      store,
      '',
      encodedEvent: EncodedEvent.streamDeleted(),
    );
    final iterator = iterate();

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.encodedEvent.isEventErased, isTrue);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.encodedEvent.isStreamDeleted, isTrue);
  });

  test('can cancel before requesting the first event', () async {
    final iterator = iterate();
    await iterator.cancel();

    expect(await iterator.moveNext(), isFalse);
  });

  test('cancels a pending moveNext while waiting for changes', () async {
    final catchUps = CallSignal();
    final iterator = iterate(caughtUp: catchUps.record);
    final next = iterator.moveNext();
    await catchUps.waitFor(1);

    await iterator.cancel();

    expect(await next, isFalse);
    expect(store.hasChangeListener, isFalse);
  });

  test(
    'cancelling replay discards remaining events without catch-up',
    () async {
      await appendProjectionEvent(store, 'first');
      await appendProjectionEvent(store, 'buffered');
      final catchUps = CallSignal();
      final iterator = iterate(caughtUp: catchUps.record);
      expect(await iterator.moveNext(), isTrue);

      await iterator.cancel();

      expect(await iterator.moveNext(), isFalse);
      expect(catchUps.count, 0);
    },
  );

  test('cancellation prevents delivery of an in-flight read', () async {
    await appendProjectionEvent(store, 'existing');
    final gate = AsyncGate();
    store.afterRead = (_) => gate.wait();
    final iterator = iterate(gates: [gate]);
    final next = iterator.moveNext();
    await gate.entered.future;

    final cancellation = iterator.cancel();
    gate.release();
    await cancellation;

    expect(await next, isFalse);
  });

  test('finishes replay when the notification stream closes', () async {
    await appendProjectionEvent(store, 'first');
    await appendProjectionEvent(store, 'second');
    final iterator = iterate();
    expect(await iterator.moveNext(), isTrue);
    final closing = store.closeChanges();

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.position, 1);
    expect(await iterator.moveNext(), isFalse);
    await closing;
  });

  test('ends a pending moveNext when the notification stream closes', () async {
    final catchUps = CallSignal();
    final iterator = iterate(caughtUp: catchUps.record);
    final next = iterator.moveNext();
    await catchUps.waitFor(1);

    await store.closeChanges();

    expect(await next, isFalse);
  });

  test('propagates a read failure and releases the subscription', () async {
    final error = StateError('read failed');
    final trace = StackTrace.fromString('read failure trace');
    store.afterRead = (_) => Future<void>.error(error, trace);
    final iterator = iterate();

    await expectLater(iterator.moveNext(), throwsA(same(error)));
    expect(await iterator.moveNext(), isFalse);
    expect(store.hasChangeListener, isFalse);
  });

  test(
    'a notification failure ends the stream with the original error',
    () async {
      final error = StateError('notification failed');
      final trace = StackTrace.fromString('notification failure trace');
      final catchUps = CallSignal();
      final iterator = iterate(caughtUp: catchUps.record);
      final expectation = expectLater(
        iterator.moveNext(),
        throwsA(same(error)),
      );
      await catchUps.waitFor(1);

      store.failNotifications(error, trace);
      await expectation;
      expect(await iterator.moveNext(), isFalse);
    },
  );

  group('catch up', () {
    test('reports catch-up when no existing events match the filter', () async {
      await appendProjectionEvent(store, 'unrelated', path: 'other');
      final catchUps = CallSignal();
      final iterator = iterate(
        filter: const LogFilter.exact('notes/one'),
        caughtUp: catchUps.record,
      );

      final next = iterator.moveNext();
      await catchUps.waitFor(1);
      await iterator.cancel();

      expect(await next, isFalse);
      expect(catchUps.count, 1);
    });

    test('reports each catch-up while continuing to follow the log', () async {
      final catchUps = CallSignal();
      final iterator = iterate(caughtUp: catchUps.record);
      final first = iterator.moveNext();
      await catchUps.waitFor(1);

      await appendProjectionEvent(store, 'first');
      expect(await first, isTrue);
      expect(iterator.current.position, 0);

      final second = iterator.moveNext();
      await catchUps.waitFor(2);
      await appendProjectionEvent(store, 'second');
      expect(await second, isTrue);
      expect(iterator.current.position, 1);

      final next = iterator.moveNext();
      await catchUps.waitFor(3);
      await iterator.cancel();
      expect(await next, isFalse);
      expect(catchUps.count, 3);
    });

    test(
      'waits for changes notified during an empty read before catch-up',
      () async {
        final catchUps = CallSignal();
        final gate = AsyncGate();
        store.afterRead = (_) => gate.wait();
        final iterator = iterate(caughtUp: catchUps.record, gates: [gate]);
        final first = iterator.moveNext();
        await gate.entered.future;

        await appendProjectionEvent(store, 'notified');
        store.afterRead = null;
        gate.release();

        expect(await first, isTrue);
        expect(iterator.current.position, 0);
        expect(catchUps.count, 0);

        final next = iterator.moveNext();
        await catchUps.waitFor(1);
        await iterator.cancel();
        expect(await next, isFalse);
        expect(catchUps.count, 1);
      },
    );
  });
}
