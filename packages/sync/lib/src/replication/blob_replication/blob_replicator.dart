import 'dart:async';

import 'package:blob/blob.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';

import 'blob_replication_channel.dart';
import 'blob_replication_exception.dart';
import 'blob_replication_message.dart';

/// Pulls bytes for command-replicated blob streams over one session.
/// Observe [run] for failures. Injected stores remain caller-owned.
class BlobReplicator {
  final BlobReplicationChannel _channel;
  final EventStoreReplication _eventStore;
  final BlobStore _blobStore;
  final Logger _logger;
  final _known = <String>{};
  final _queued = <String>{};
  final _done = Completer<void>();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _work = Future.value();
  Future<void>? _closing;
  String? _pending;
  bool _announcedWhilePending = false;
  bool _started = false;
  bool _closed = false;
  Object? _failure;
  StackTrace? _stack;

  BlobReplicator({
    required this._channel,
    required this._eventStore,
    required this._blobStore,
    required this._logger,
  });

  /// Starts once, scanning existing metadata before continuing with changes.
  Future<void> run() {
    if (_started) throw StateError('BlobReplicator already started');
    _started = true;
    try {
      unawaited(_channel.sink.done.then<void>((_) {}, onError: _fail));
      _subscriptions.add(
        _channel.stream.listen(
          (message) => _enqueue(() => _receive(message)),
          onError: _fail,
          onDone: () => unawaited(close()),
        ),
      );
      _subscriptions.add(
        _eventStore.eventChanges.listen(
          (change) => _enqueue(() => _discover(change.stream)),
          onError: _fail,
        ),
      );
      _subscriptions.add(
        _blobStore.availableBlobs.listen(
          (id) => _enqueue(() async {
            _channel.sink.add(BlobReplicationMessageAvailable(blobId: id));
          }),
          onError: _fail,
        ),
      );
      _enqueue(() => _scan(0));
    } catch (error, stack) {
      _fail(error, stack);
    }
    return _done.future;
  }

  void _enqueue(Future<void> Function() action) {
    if (_closed) return;
    _work = _work.then((_) async {
      if (_closed) return;
      try {
        await action();
      } catch (error, stack) {
        _fail(error, stack);
      }
    });
  }

  Future<void> _scan(int cursor) async {
    final page = await _eventStore.getLogEvents(
      const LogFilter.startsWith('_blob/'),
      cursor,
    );
    if (_closed) return;
    for (final event in page.data) {
      await _discover(event.streamPath);
      if (_closed) return;
    }
    if (page.next != null && page.data.isNotEmpty) {
      _enqueue(() => _scan(page.next!));
    }
  }

  Future<void> _discover(String stream) async {
    final id = _blobIdFromStream(stream);
    if (id == null || !_known.add(id)) return;
    _queued.add(id);
    await _pull();
  }

  Future<void> _pull() async {
    while (!_closed && _pending == null && _queued.isNotEmpty) {
      final id = _queued.first;
      _queued.remove(id);
      final bytes = await _blobStore.get(id);
      if (_closed) return;
      if (bytes != null) continue;
      _pending = id;
      _announcedWhilePending = false;
      _channel.sink.add(BlobReplicationMessageRequest(blobId: id));
    }
  }

  Future<void> _receive(BlobReplicationMessage message) async {
    final id = message.blobId;
    switch (message) {
      case BlobReplicationMessageRequest():
        final bytes = await _blobStore.get(id);
        if (_closed) return;
        _channel.sink.add(
          bytes == null
              ? BlobReplicationMessageMissing(blobId: id)
              : BlobReplicationMessageData(blobId: id, bytes: bytes),
        );
      case BlobReplicationMessageAvailable():
        if (!_known.contains(id)) return;
        if (_pending == id) {
          _announcedWhilePending = true;
        } else {
          _queued.add(id);
        }
      case BlobReplicationMessageData():
        if (_pending != id) {
          throw const BlobReplicationException('Unexpected blob response');
        }
        await _blobStore.save(id, message.bytes);
        if (_closed) return;
        _pending = null;
        _announcedWhilePending = false;
      case BlobReplicationMessageMissing():
        if (_pending != id) {
          throw const BlobReplicationException('Unexpected blob response');
        }
        if (_announcedWhilePending) {
          _queued.add(id);
        }
        _pending = null;
        _announcedWhilePending = false;
    }
    await _pull();
  }

  void _fail(Object error, StackTrace stack) {
    if (_done.isCompleted) return;
    _failure ??= error;
    _stack ??= stack;
    _logger.error('Blob replication session failed');
    unawaited(close());
  }

  /// Stops subscriptions and waits for already started storage operations.
  Future<void> close() {
    if (!_started) throw StateError('BlobReplicator has not started');
    _closed = true;
    return _closing ??= Future<void>.microtask(() async {
      Future<void> clean(Future<void> Function() action) async {
        try {
          await action();
        } catch (error, stack) {
          _failure ??= error;
          _stack ??= stack;
        }
      }

      await Future.wait([
        clean(_channel.sink.close),
        for (final subscription in _subscriptions) clean(subscription.cancel),
      ]);
      await _work;
      if (_failure == null) {
        _done.complete();
      } else {
        _done.completeError(_failure!, _stack);
      }
    });
  }
}

String? _blobIdFromStream(String stream) {
  const prefix = '_blob/';
  return stream.startsWith(prefix) && stream.length > prefix.length
      ? stream.substring(prefix.length)
      : null;
}
