import 'dart:async';

import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

import 'projection_test_support.dart';

void main() {
  late ControlledMemoryEventStore store;
  late CqrsTestRuntime runtime;

  setUp(() {
    store = ControlledMemoryEventStore();
    runtime = CqrsTestRuntime(eventStore: store);
    addTearDown(store.closeChanges);
  });

  StreamIterator<StoredEvent> iterate({
    LogFilter filter = const LogFilter.all(),
    int fromPosition = 0,
    List<AsyncGate> gates = const [],
  }) {
    final iterator = StreamIterator(
      runtime.logIterator(filter, fromPosition: fromPosition),
    );
    addTearDown(() async {
      for (final gate in gates) {
        gate.release();
      }
      await iterator.cancel();
    });
    return iterator;
  }

  test(
    'replays existing events from zero across pages without a change',
    () async {
      for (var index = 0; index < 3; index++) {
        await appendProjectionEvent(store, '$index');
      }
      final iterator = iterate();

      for (var position = 0; position < 3; position++) {
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current.position, position);
      }
      expect(store.subscriptions.count, 1);
    },
  );

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
    test('filters $name matches across pages', () async {
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

  test('waits on an empty log and resumes after each catch-up', () async {
    final iterator = iterate();
    final first = iterator.moveNext();
    await store.emptyReads.waitFor(1);

    await appendProjectionEvent(store, 'first');
    expect(await first, isTrue);
    expect(iterator.current.position, 0);

    final second = iterator.moveNext();
    await store.emptyReads.waitFor(2);
    await appendProjectionEvent(store, 'second');
    expect(await second, isTrue);
    expect(iterator.current.position, 1);
  });

  test('ignores changes outside its filter while following the log', () async {
    final iterator = iterate(filter: const LogFilter.exact('notes/one'));
    final next = iterator.moveNext();
    await store.emptyReads.waitFor(1);

    await appendProjectionEvent(store, 'ignored', path: 'other');
    await store.notifications.waitFor(1);
    await appendProjectionEvent(store, 'matching');

    expect(await next, isTrue);
    expect(iterator.current.position, 1);
    expect(iterator.current.streamPath, 'notes/one');
  });

  for (final initiallyEmpty in [true, false]) {
    test('observes commits during an ${initiallyEmpty ? 'empty' : 'existing'} '
        'initial page read', () async {
      if (!initiallyEmpty) await appendProjectionEvent(store, 'existing');
      final gate = AsyncGate();
      store.afterRead = (_) => gate.wait();
      final iterator = iterate(gates: [gate]);
      final first = iterator.moveNext();
      await gate.entered.future;
      expect(store.hasChangeListener, isTrue);

      final notificationCount = store.notifications.count;
      await appendProjectionEvent(store, 'concurrent');
      await store.notifications.waitFor(notificationCount + 1);
      store.afterRead = null;
      gate.release();

      expect(await first, isTrue);
      expect(iterator.current.position, 0);
      if (!initiallyEmpty) {
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current.position, 1);
      }
    });
  }

  test('delivers commits accumulated while paused once in log order', () async {
    await appendProjectionEvent(store, 'first');
    final iterator = iterate();
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.position, 0);

    for (var index = 1; index <= 3; index++) {
      await appendProjectionEvent(store, '$index');
    }
    await store.notifications.waitFor(4);
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

  test('coalesces a notification burst into one pending replay', () async {
    await appendProjectionEvent(store, 'first');
    final iterator = iterate();
    expect(await iterator.moveNext(), isTrue);
    await store.notifications.waitFor(1);

    for (var index = 0; index < 100; index++) {
      store.notify('notes/one');
    }
    final closing = store.closeChanges();
    expect(await iterator.moveNext(), isFalse);
    await closing;

    // Finishing the active replay and its pending replay each find an empty page.
    expect(store.emptyReads.count, lessThanOrEqualTo(2));
  });

  test('can cancel before the first moveNext without subscribing', () async {
    final iterator = iterate();
    await iterator.cancel();

    expect(await iterator.moveNext(), isFalse);
    expect(store.subscriptions.count, 0);
  });

  test('cancels a pending moveNext while waiting for changes', () async {
    final iterator = iterate();
    final next = iterator.moveNext();
    await store.emptyReads.waitFor(1);

    await iterator.cancel();

    expect(await next, isFalse);
    expect(store.hasChangeListener, isFalse);
    expect(store.cancellations.count, 1);
  });

  test('releases its subscription when cancelled while paused', () async {
    await appendProjectionEvent(store, 'first');
    await appendProjectionEvent(store, 'buffered');
    final iterator = iterate();
    expect(await iterator.moveNext(), isTrue);

    await iterator.cancel();

    expect(await iterator.moveNext(), isFalse);
    expect(store.hasChangeListener, isFalse);
    expect(store.cancellations.count, 1);
  });

  test(
    'finishes cancellation after an active storage read is released',
    () async {
      final gate = AsyncGate();
      store.afterRead = (_) => gate.wait();
      final iterator = iterate(gates: [gate]);
      final next = iterator.moveNext();
      await gate.entered.future;

      final cancellation = iterator.cancel();
      gate.release();
      await cancellation;

      expect(await next, isFalse);
      expect(store.hasChangeListener, isFalse);
    },
  );

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
    expect(store.hasChangeListener, isFalse);
  });

  test('ends a pending moveNext when the notification stream closes', () async {
    final iterator = iterate();
    final next = iterator.moveNext();
    await store.emptyReads.waitFor(1);

    await store.closeChanges();

    expect(await next, isFalse);
  });

  for (final source in ['read', 'notification']) {
    test(
      'propagates a $source failure and releases the subscription',
      () async {
        final error = StateError('$source failed');
        final trace = StackTrace.fromString('$source failure trace');
        if (source == 'read') {
          store.afterRead = (_) => Future<void>.error(error, trace);
        }
        final iterator = iterate();
        final expectation = expectLater(
          iterator.moveNext(),
          throwsA(same(error)),
        );
        if (source == 'notification') {
          await store.emptyReads.waitFor(1);
          store.failNotifications(error, trace);
        }

        await expectation;
        await store.cancellations.waitFor(1);
        expect(store.hasChangeListener, isFalse);
        expect(await iterator.moveNext(), isFalse);
      },
    );
  }
}
