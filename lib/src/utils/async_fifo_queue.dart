import 'dart:async';
import 'dart:collection';

typedef AsyncQueueTask<T> = Future<void> Function(T value);
typedef AsyncQueueErrorHandler =
    void Function(Object error, StackTrace stackTrace);

class AsyncFIFOQueue<T> {
  final AsyncQueueTask<T> _task;

  final Queue<_QueueItem<T>> _queue = Queue<_QueueItem<T>>();
  final List<_Waiter> _waiters = [];

  bool _processing = false;
  int _currentSequence = 0;
  int _latestSequence = 0;

  AsyncFIFOQueue(this._task);

  int get currentSequence => _currentSequence;
  int get latestSequence => _latestSequence;
  bool get isEmpty => _queue.isEmpty && !_processing;

  void enqueue(T value, int sequence) {
    if (sequence <= _latestSequence) {
      throw ArgumentError(
        'Sequence $sequence must be > latest $_latestSequence',
      );
    }
    _latestSequence = sequence;
    _queue.add(_QueueItem(value, sequence));

    // TODO: can use microtasks to mirror js implementation
    // could be racy if the underlying implementation is fake async
    // as could be the case sometimes with memory repos
    // im gonna keep it for now and we go from there
    scheduleMicrotask(_processNext);
    // _processNext();
  }

  void onReached(int targetSequence, void Function() callback) {
    if (_currentSequence >= targetSequence) {
      callback();
      return;
    }
    _waiters.add(_Waiter(targetSequence, callback));
  }

  void reset() {
    _queue.clear();
    _processing = false;
    _currentSequence = 0;
    _latestSequence = 0;
    _waiters.clear();
  }

  // dont use in real code. Useful during testing though
  Future<void> testWaitFor(int targetSequence) {
    if (_currentSequence >= targetSequence) {
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(_Waiter(targetSequence, () => completer.complete()));
    return completer.future;
  }

  Future<void> testWaitForLatest() {
    return testWaitFor(_latestSequence);
  }

  void _processNext() {
    if (_processing) return;
    if (_queue.isEmpty) {
      _flushReadyWaiters();
      return;
    }

    _processing = true;
    final item = _queue.removeFirst();

    _task(item.value)
        .then((_) {
          _currentSequence = item.sequence;
          _processing = false;
          _flushReadyWaiters();
          _processNext();
        })
        .catchError((Object e, StackTrace st) {
          _processing = false;

          // Flush ALL waiters on error "just in case".
          _flushAllWaiters();

          // Then clear queue/state.
          reset();

          // the task should never throw
          // the tasks must swallow exceptions and process them internally.
          Error.throwWithStackTrace(e, st);
        });
  }

  void _flushReadyWaiters() {
    if (_waiters.isEmpty) return;
    final ready = _waiters.where((w) => _currentSequence >= w.target).toList();
    _waiters.removeWhere((w) => _currentSequence >= w.target);
    for (final w in ready) {
      w.callback();
    }
  }

  void _flushAllWaiters() {
    if (_waiters.isEmpty) return;
    final pending = List<_Waiter>.from(_waiters);
    _waiters.clear();
    for (final w in pending) {
      w.callback();
    }
  }
}

class _QueueItem<T> {
  final T value;
  final int sequence;
  const _QueueItem(this.value, this.sequence);
}

class _Waiter {
  final int target;
  final void Function() callback;
  const _Waiter(this.target, this.callback);
}
