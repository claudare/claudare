import 'dart:collection';

typedef AsyncQueueTask<T> = Future<void> Function(T value);

class AsyncFIFOQueue<T> {
  final AsyncQueueTask<T> _task;
  final Queue<_QueueItem<T>> _queue = Queue<_QueueItem<T>>();

  bool _processing = false;
  int _size = 0;

  AsyncFIFOQueue(this._task);

  int get size => _size;

  bool get isEmpty => _queue.isEmpty && !_processing;

  void enqueue(T value, {required void Function()? onDone}) {
    _queue.add(_QueueItem(value, onDone: onDone));
    _size++;

    _processNext();
  }

  void reset() {
    for (final item in _queue) {
      item.onDone?.call();
    }
    _queue.clear();
    _size = 0;
    _processing = false;
  }

  void _processNext() {
    if (_processing) return;
    if (_queue.isEmpty) return;

    _processing = true;
    final item = _queue.removeFirst();

    _task(item.value)
        .then((_) {
          item.onDone?.call();
          _size--;

          _processing = false;
          _processNext();
        })
        .catchError((Object e, StackTrace st) {
          _processing = false;
          reset();

          Error.throwWithStackTrace(e, st);
        });
  }
}

class _QueueItem<T> {
  final T value;
  final void Function()? onDone;

  const _QueueItem(this.value, {this.onDone});
}
