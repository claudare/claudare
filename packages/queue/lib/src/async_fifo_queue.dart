import 'dart:collection';

typedef AsyncQueueTask<T> = Future<void> Function(T value);

class AsyncFIFOQueue<T> {
  final AsyncQueueTask<T> _task;
  final Queue<_QueueItem<T>> _queue = Queue<_QueueItem<T>>();

  bool _processing = false;
  int _currentSequence = 0;
  int _latestSequence = 0;
  int _size = 0;

  AsyncFIFOQueue(this._task);

  int get currentSequence => _currentSequence;
  int get latestSequence => _latestSequence;
  int get size => _size;

  bool get isEmpty => _queue.isEmpty && !_processing;

  void enqueue(T value, int sequence, {required void Function()? onDone}) {
    if (sequence <= _latestSequence) {
      throw ArgumentError(
        'Sequence $sequence must be > latest $_latestSequence',
      );
    }

    _latestSequence = sequence;
    _queue.add(_QueueItem(value, sequence, onDone: onDone));
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
    _currentSequence = 0;
    _latestSequence = 0;
  }

  void _processNext() {
    if (_processing) return;
    if (_queue.isEmpty) return;

    _processing = true;
    final item = _queue.removeFirst();

    _task(item.value)
        .then((_) {
          _currentSequence = item.sequence;

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
  final int sequence;
  final void Function()? onDone;

  const _QueueItem(this.value, this.sequence, {this.onDone});
}
