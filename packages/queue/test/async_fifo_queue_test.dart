import 'dart:async';

import 'package:queue/queue.dart';
import 'package:test/test.dart';

void main() {
  test('processes tasks one at a time in FIFO order', () async {
    final firstTask = Completer<void>();
    final secondTask = Completer<void>();
    final started = <int>[];
    final completed = <int>[];
    final queue = AsyncFIFOQueue<int>((value) {
      started.add(value);
      return switch (value) {
        1 => firstTask.future,
        2 => secondTask.future,
        _ => throw StateError('Unexpected value: $value'),
      };
    });

    queue.enqueue(1, onDone: () => completed.add(1));
    queue.enqueue(2, onDone: () => completed.add(2));

    expect(started, [1]);
    expect(queue.size, 2);
    expect(queue.isEmpty, isFalse);

    firstTask.complete();
    await firstTask.future;
    await Future<void>.delayed(Duration.zero);

    expect(started, [1, 2]);
    expect(completed, [1]);
    expect(queue.size, 1);

    secondTask.complete();
    await secondTask.future;
    await Future<void>.delayed(Duration.zero);

    expect(completed, [1, 2]);
    expect(queue.size, 0);
    expect(queue.isEmpty, isTrue);
  });

  test('enqueueAndWait completes after the task finishes', () async {
    final task = Completer<void>();
    final queue = AsyncFIFOQueue<int>((_) => task.future);
    var completed = false;

    final done = queue.enqueueAndWait(1).then((_) => completed = true);

    expect(completed, isFalse);

    task.complete();
    await done;

    expect(completed, isTrue);
  });

  test('enqueueAndWait completes when reset releases a pending item', () async {
    final activeTask = Completer<void>();
    final queue = AsyncFIFOQueue<int>((_) => activeTask.future);

    queue.enqueue(1, onDone: null);
    final pendingDone = queue.enqueueAndWait(2);

    queue.reset();

    await pendingDone;
  });
}
