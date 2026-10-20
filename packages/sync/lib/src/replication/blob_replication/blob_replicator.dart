import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';

import '../../sync_defaults.dart';
import 'blob_replication_channel.dart';
import 'blob_replication_exception.dart';
import 'blob_replication_message.dart';

/// Pulls pending blobs and serves complete bytes over one protocol session.
///
/// Null storage disables downloads and responds to requests with missing.
/// Requests wait for a matching response or session closure.
/// Observe [run] for failures and create a new worker and channel to restart.
/// Each worker starts its pending scan from zero.
/// Injected stores remain caller-owned.
class BlobReplicator {
  final BlobReplicationChannel _channel;
  final EventStoreReplication _eventStore;
  final BlobStore? _blobStore;
  final Logger _logger;
  final Timer Function(Duration delay, void Function() callback) _timerFactory;
  final Duration retryInterval;
  final _done = Completer<void>();

  StreamSubscription<BlobReplicationMessage>? _messages;
  StreamSubscription<CommandChange>? _changes;
  Timer? _retryTimer;
  Completer<BlobReplicationMessage?>? _response;
  String? _requested;
  Future<void>? _closing;
  Object? _failure;
  StackTrace? _failureStack;
  int _cursor = 0;
  bool _started = false;
  bool _closed = false;
  bool _serving = false;
  bool _scanning = false;
  bool _wakePending = false;
  bool _rescanPending = false;

  BlobReplicator({
    required this._channel,
    required this._eventStore,
    required this._blobStore,
    required this._logger,
    this.retryInterval = SyncDefaults.blobRetryInterval,
    this._timerFactory = Timer.new,
  }) {
    if (retryInterval <= Duration.zero) {
      throw ArgumentError.value(retryInterval, 'retryInterval');
    }
  }

  /// Starts once and completes on closure, or fails with the original error.
  /// New command changes wake the scan without waiting for periodic retries.
  Future<void> run() {
    if (_started) throw StateError('BlobReplicator has already been started');
    _started = true;
    try {
      unawaited(
        _channel.sink.done.then<void>((_) {
          unawaited(close());
        }, onError: _fail),
      );
      _messages = _channel.stream.listen(
        _receive,
        onError: _fail,
        onDone: () => unawaited(close()),
      );
      if (_blobStore != null) {
        _changes = _eventStore.commandChanges.listen(
          (_) => _wake(),
          onError: _fail,
        );
        _wake();
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
    return _done.future;
  }

  void _wake({bool fromBeginning = false}) {
    if (_closed || _blobStore == null) return;
    _wakePending = true;
    _rescanPending |= fromBeginning;
    if (_scanning) return;
    _scanning = true;
    unawaited(_scan());
  }

  Future<void> _scan() async {
    try {
      do {
        _wakePending = false;
        if (_rescanPending) {
          _rescanPending = false;
          _cursor = 0;
        }
        await _scanPass();
        if (_closed) return;
        _retryTimer ??= _timerFactory(retryInterval, () {
          _retryTimer = null;
          _wake(fromBeginning: true);
        });
      } while (_wakePending);
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _scanning = false;
    }
  }

  Future<void> _scanPass() async {
    while (!_closed) {
      final page = await _eventStore.getPendingBlobIds(_cursor);
      if (_closed) return;
      if (page.data.isEmpty) return;
      _cursor = page.next!;
      for (final blobId in page.data) {
        final status = await _eventStore.getBlobStatus(blobId);
        if (_closed) return;
        if (status != BlobStatus.pending) continue;
        final response = await _request(blobId);
        if (_closed || response == null) return;
        if (response is BlobReplicationMessageData) {
          await _blobStore!.save(blobId, response.bytes);
          await _eventStore.markBlobAvailable(blobId);
          if (_closed) return;
        }
      }
    }
  }

  Future<BlobReplicationMessage?> _request(String blobId) {
    final response = _response = Completer<BlobReplicationMessage?>();
    _requested = blobId;
    _channel.sink.add(BlobReplicationMessageRequest(blobId: blobId));
    return response.future;
  }

  void _receive(BlobReplicationMessage message) {
    if (_closed) return;
    if (message is BlobReplicationMessageRequest) {
      if (_serving) {
        _fail(
          const BlobReplicationException('Overlapping blob request'),
          StackTrace.current,
        );
      } else {
        _serving = true;
        unawaited(_serve(message.blobId));
      }
      return;
    }
    final response = _response;
    if (response == null || message.blobId != _requested) {
      _fail(
        const BlobReplicationException('Unexpected blob response'),
        StackTrace.current,
      );
      return;
    }
    _response = null;
    _requested = null;
    response.complete(message);
  }

  Future<void> _serve(String blobId) async {
    try {
      final bytes = await _blobStore?.get(blobId);
      if (_closed) return;
      _serving = false;
      _channel.sink.add(
        bytes == null
            ? BlobReplicationMessageMissing(blobId: blobId)
            : BlobReplicationMessageData(blobId: blobId, bytes: bytes),
      );
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _recordFailure(Object error, StackTrace stack) {
    if (_failure != null) return;
    _failure = error;
    _failureStack = stack;
    _logger.error('Blob replication session failed');
  }

  void _fail(Object error, StackTrace stack) {
    if (_closed) return;
    _recordFailure(error, stack);
    unawaited(close());
  }

  /// Stops both directions and releases subscriptions and pending requests.
  /// Active storage calls may finish, but their results are ignored afterward.
  Future<void> close() {
    if (!_started) throw StateError('BlobReplicator has not been started');
    if (_closed) return _closing!;
    _closed = true;
    _retryTimer?.cancel();
    _response?.complete(null);
    _response = null;
    _requested = null;
    return _closing = Future<void>.microtask(_cleanup);
  }

  Future<void> _cleanup() async {
    await Future.wait([
      _cleanupOperation(_channel.sink.close),
      _cleanupOperation(() async => _messages?.cancel()),
      _cleanupOperation(() async => _changes?.cancel()),
    ]);
    final failure = _failure;
    if (failure == null) {
      _done.complete();
    } else {
      _done.completeError(failure, _failureStack);
    }
  }

  Future<void> _cleanupOperation(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error, stack) {
      _recordFailure(error, stack);
    }
  }
}
